(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 08_Robot
   Worksheet : FB - SP_RobMotion
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE ADAPTER - kinematic group motion control for one
               robot. ALL firmware group/motion calls of SmartPick live in
               this FB body (never in methods, never elsewhere).

   Handshake: the caller (SP_Robot) writes the motion parameters and
   increments udiSeq; the adapter fires the move on the sequence change,
   publishes bBusy/bDone (PLCopen level-based Execute handled internally).

   FW BINDING (CONFIRM against the installed iCube motion library):
     - GroupEnable / GroupStop / GroupReset : PLCopen Part 4 names.
     - MC_MoveLinearAbsolute                : PLCopen Part 4 linear move with
       CoordSystem + BufferMode inputs. Used for BOTH the static MCS moves
       and (with CoordSystem = PCS) the belt-synchronized moves.
     - MC_TrackConveyorBelt (FW-1, CLOSED IN CODE v1.3): PLCopen Part 4
       tracking FB - synchronizes the group with a conveyor belt axis and
       keeps the PCS moving with the product. Interface per the PLCopen
       Part 4 spec (6.6) plus the Yaskawa extensions documented in the
       iCube Control release notes 2025-6 / 2026-6:
         * ConveyorBelt : AXIS_REF (VAR_IN_OUT) - the belt encoder axis
           (external encoder master axes are supported).
         * ConveyorBeltOrigin      : belt CS pose in MCS, x-axis along the
           belt travel direction.
         * InitialObjectPosition   : product pose in the belt CS (fixed at
           capture; the firmware keeps it aligned to the belt encoder).
         * ExecutionMode           : MC_ExecutionMode (Immediately/Delayed/
           Queued) - Yaskawa extension.
         * TrackOptions.SyncIn.ConveyorDistance > 0 - Yaskawa extension,
           0 reports error 9006 since FW 2026.6.
         * InSync/TrackState outputs - Yaskawa extension (group synchronized
           with the belt).
       The spellings of MC_COORDSYS / MC_BUFFER_MODE / MC_ExecutionMode /
       the TrackOptions struct are CONFIRM items (one line each, see
       Firmware/FW_PATCH_ConveyorTracking_IT-EN.md section 2.4).
     - Group actual position: assumed MC_GroupReadActualPosition with a
       Position[1..3] output array; adapt the CONFIRM mapping if different.
     - Homing: bHomed is consumed by the robot FSM; axis-level homing is
       expected at machine level (HMI / integrator program).
     - Group status (FW-2): bEnabled/bHomed come either from the proxy mode
       (g_eFwStatMode = 0, default) or from the injected status inputs
       bFwReadyIn/bFwRefIn (g_eFwStatMode = 1) wired by PRG_SP_TaskFast from
       GVL_SP_Fw.

   TRACKING MODES (selected per move by the caller through bTrkReq; the
   master switch GVL_SP_Fw.g_eTrkMode stays in SP_Robot):
     FALSE = FALLBACK (v1.x behavior, simulation-safe): the tracked move
         goes to the cut-off predicted WORLD pose as a plain MCS linear
         move. Works without the tracking option; pick accuracy degrades
         with belt speed (tolerance >= +/-5 mm up to ~0.3-0.5 m/s).
     TRUE = NATIVE: a MC_TrackConveyorBelt session is opened at the first
         tracked move of a pick leg; the tracked (and depart) moves are
         commanded in PCS to the product-fixed pose; the NEXT static MCS
         move ends the session (BufferMode Aborting, documented behavior).
         Full-speed flying pick with firmware-managed belt following.

   SESSION LIFECYCLE (native mode):
     TrackAbs request edge  -> open session (Execute pulse, Immediate mode)
                            -> wait Active (watchdog 2 s) -> PCS move.
     Next LinearAbs request -> MCS move with Aborting -> drop Execute.
     Stop / fault / pause   -> drop Execute + group stop (session lost,
                            resume re-opens a fresh session; the belt-frame
                            product pose is capture-fixed, so nothing is
                            lost - MotoPick 4 pause semantics preserved).
   =============================================================================
*)

FUNCTION_BLOCK SP_RobMotion
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bSim    : BOOL;             (* TRUE = kinematic simulation, no FW *)
    bEnable : BOOL;             (* Group enable command *)
    bStopReq: BOOL;             (* Controlled stop request *)
    bReset  : BOOL;             (* Fault reset request *)
    uiDtMs  : UDINT;            (* Task period [ms] *)
    (* Move request (fired on udiSeq change) *)
    udiSeq  : UDINT;            (* Request sequence counter *)
    eMv     : ET_SP_MvKind;     (* Move kind *)
    stTarget: ST_SP_Pose3D;     (* Target pose WORLD/MCS [mm, rad] *)
    rVel    : LREAL;            (* Path velocity [mm/s] *)
    rAcc    : LREAL;            (* Acceleration [mm/s2] *)
    rDec    : LREAL;            (* Deceleration [mm/s2] *)
    rZone   : LREAL;            (* Corner zone radius [mm] (precision mode) *)
    rBeltSpd: LREAL;            (* Belt speed for tracked moves [mm/s] (fallback diagnostics) *)
    (* FW-1 native tracking session data (consumed when bTrkReq = TRUE) *)
    stTargetBelt: ST_SP_Pose3D; (* Target of the armed move in the BELT CS/PCS [mm, rad] *)
    stBeltOrg   : ST_SP_Pose3D; (* Belt CS origin in MCS, x-axis along belt travel *)
    stObjBelt   : ST_SP_Pose3D; (* Product pose in the belt CS at capture (session anchor) *)
    rSyncDist   : LREAL;        (* TrackOptions.SyncIn.ConveyorDistance [mm], > 0 *)
    bTrkReq     : BOOL;         (* TRUE = the armed TrackAbs move runs native tracked
                                   (policy: GVL_SP_Fw.g_eTrkMode AND feed wired, by SP_Robot) *)
    (* FW-2 status injection (active when GVL_SP_Fw.g_eFwStatMode = 1) *)
    bFwReadyIn : BOOL;          (* Real group enabled/ready status *)
    bFwRefIn   : BOOL;          (* Real group referenced/homed status *)
END_VAR
VAR_OUTPUT
    bEnabled : BOOL;            (* Group enabled *)
    bHomed   : BOOL;            (* Group ready (referenced) *)
    bBusy    : BOOL;            (* Move in progress *)
    bDone    : BOOL;            (* One-cycle pulse: move finished *)
    bErr     : BOOL;            (* Move error pulse *)
    uiErrId  : UINT;            (* Error id (1 robot layer, 201/202 tracking session) *)
    p2Now    : ST_SP_Pose2D;    (* Current world pose [mm, rad] *)
    rZNow    : LREAL;           (* Current Z [mm] *)
    bTrkSess : BOOL;            (* FW-1: tracking session open or releasing *)
    bTrkInSync: BOOL;           (* FW-1: group synchronized with the belt (Active) *)
END_VAR
VAR_IN_OUT
    ioGrp : AXES_GROUP_REF;     (* Firmware kinematic group *)
    ioBelt: AXIS_REF;           (* FW-1: conveyor belt encoder axis (per pick feed) *)
END_VAR
VAR
    (* CONFIRM: PLCopen Part 4 group FB instances *)
    m_fbEn   : GroupEnable;
    (* PLCopen Part 4 group stop instance (firmware adapter) *)
    m_fbStop : GroupStop;
    (* PLCopen Part 4 group reset instance *)
    m_fbRst  : GroupReset;
    (* Linear move instance (static MCS AND synchronized PCS moves) *)
    m_fbLin  : MC_MoveLinearAbsolute;
    (* FW-1: PLCopen Part 4 conveyor tracking instance (session transform) *)
    m_fbTrk  : MC_TrackConveyorBelt;
    (* Group position reader (status polling) *)
    m_fbPos  : MC_GroupReadActualPosition;
    (* Session start watchdog (Active must come within 2 s) *)
    m_fbTrkTo: TON;
    (* Request edge / move execution state *)
    m_udiSeqPrev : UDINT := 0;
    m_bMvExec : BOOL;           (* Held Execute for the active move *)
    (* FW-1 session state *)
    m_bTrkSess : BOOL;          (* Session open (tracking requested and not yet released) *)
    m_bTrkExec : BOOL;          (* Held Execute of m_fbTrk (TRUE for the whole session) *)
    m_bTrkRel  : BOOL;          (* Release pending: waiting for Active = FALSE *)
    m_bTrkArm  : BOOL;          (* Tracked move armed, waiting for Active before firing *)
    m_bTrkDrop : BOOL;          (* TRUE = drop the session when the closing MCS move finishes *)
    (* CONFIRM: Yaskawa TrackOptions struct (SyncIn.ConveyorDistance > 0) *)
    m_stTrkOpt : ST_SP_TrkOpt;
    (* CONFIRM: PLCopen ConveyorBeltOrigin array (X, Y, Z, Theta) *)
    m_arrCbOrg : ARRAY[1..4] OF LREAL;
    (* CONFIRM: PLCopen InitialObjectPosition array (X, Y, Z, Theta) *)
    m_arrObjIni: ARRAY[1..4] OF LREAL;
    (* Firmware feedback copies *)
    m_bLinDone : BOOL;
    (* Copy of m_fbLin.Busy *)
    m_bLinBusy : BOOL;
    (* Copy of m_fbLin.Aborted *)
    m_bLinAbort: BOOL;
    (* Copy of m_fbLin.Error *)
    m_bLinErr  : BOOL;
    (* Copy of m_fbLin.ErrorID *)
    m_uiLinErr : UINT;
    (* Tracking FB feedback copies *)
    m_bTrkBusy : BOOL;          (* Copy of m_fbTrk.Busy *)
    m_bTrkActi : BOOL;          (* Copy of m_fbTrk.Active (transform running) *)
    m_bTrkErr  : BOOL;          (* Copy of m_fbTrk.Error *)
    m_bTrkAbort: BOOL;          (* Copy of m_fbTrk.CommandAborted *)
    m_uiTrkErr : UINT;          (* Copy of m_fbTrk.ErrorID *)
    (* Simulated kinematics *)
    m_p2Sim : ST_SP_Pose2D;
    (* Simulated Z height [mm] (offline kinematics) *)
    m_rZSim : LREAL := 100.0;
    (* Task period [s] for the simulation integrator *)
    m_rDtSec: LREAL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bDone := FALSE;
bErr  := FALSE;
m_rDtSec := UDINT_TO_LREAL(uiDtMs) / 1000.0;

IF bSim THEN
    THIS.SimBody();
    RETURN;
END_IF

(* -------------------------- Hardware path ------------------------------ *)
(* 1) Group enable (level based) ------------------------------------------ *)
m_fbEn(
    AxesGroup := ioGrp,
    Execute   := bEnable,
    Done      => ,
    Busy      => ,
    Error     => ,
    ErrorID   =>
);
(* FW-2 resolution: status proxy (default) or injected group status.
   The injection mode is selected by GVL_SP_Fw.g_eFwStatMode, so the
   on-site binding is a wiring task in PRG_SP_TaskFast, not a code edit. *)
IF GVL_SP_Fw.g_eFwStatMode = 1 THEN
    bEnabled := bFwReadyIn;     (* Real group ready bit *)
    bHomed   := bFwRefIn;       (* Real group referenced bit *)
ELSE
    bEnabled := bEnable;        (* Proxy: CONFIRM against GroupEnable.Done
                                   when the library exposes it *)
    bHomed   := bEnabled;       (* Proxy: CONFIRM group referenced status *)
END_IF

(* 2) Controlled stop (level while requested) ------------------------------ *)
IF bStopReq THEN
    m_bMvExec := FALSE;     (* Aborts the pending move execution *)
    m_bTrkArm := FALSE;
    m_bTrkDrop := FALSE;
    IF m_bTrkSess OR m_bTrkExec THEN
        (* Drop the belt session with the stop: the next tracked move
           re-opens a fresh session (capture-fixed belt pose, nothing lost) *)
        m_bTrkSess := FALSE;
        m_bTrkExec := FALSE;
        m_bTrkRel  := TRUE;
    END_IF
    m_fbStop(
        AxesGroup := ioGrp,
        Execute   := TRUE,
        Deceleration := rDec,
        Done      => ,
        Busy      => ,
        Error     => ,
        ErrorID   =>
    );
    bBusy := FALSE;
    m_udiSeqPrev := udiSeq; (* Drop the stale request *)
    m_fbPos(
        AxesGroup := ioGrp,
        Enable    := TRUE,
        Valid     => ,
        Busy      => ,
        Error     => ,
        ErrorID   =>
    );
    (* CONFIRM: map the library position outputs, e.g.
       p2Now.rX := m_fbPos.Position[1];
       p2Now.rY := m_fbPos.Position[2];
       rZNow    := m_fbPos.Position[3];  (orientation per library) *)
    RETURN;
END_IF

(* 3) Fault reset (edge) ---------------------------------------------------- *)
IF bReset THEN
    m_fbRst(
        AxesGroup := ioGrp,
        Execute   := TRUE,
        Done      => ,
        Busy      => ,
        Error     => ,
        ErrorID   =>
    );
END_IF

(* 4) Actual position ------------------------------------------------------- *)
m_fbPos(
    AxesGroup := ioGrp,
    Enable    := TRUE,
    Valid     => ,
    Busy      => ,
    Error     => ,
    ErrorID   =>
);
(* CONFIRM: map the library position outputs, e.g.
   p2Now.rX := m_fbPos.Position[1];
   p2Now.rY := m_fbPos.Position[2];
   rZNow    := m_fbPos.Position[3];  (orientation per library) *)

(* 5) Move request edge ------------------------------------------------------ *)
IF (udiSeq <> m_udiSeqPrev) AND (eMv <> ET_SP_MvKind#None) THEN
    IF (eMv = ET_SP_MvKind#TrackAbs) AND bTrkReq THEN
        IF NOT m_bTrkSess THEN
            (* Open the tracking session: fill the frame data from the
               pick reservation carried by the caller (CONFIRM array
               layout [X, Y, Z, Theta] against the library REAL/LREAL;
               Theta is in DEGREES per the application units convention,
               matching the Yaskawa MCS orientation unit - CONFIRM). *)
            m_arrCbOrg[1] := stBeltOrg.rX;
            m_arrCbOrg[2] := stBeltOrg.rY;
            m_arrCbOrg[3] := stBeltOrg.rZ;
            m_arrCbOrg[4] := stBeltOrg.rTh;
            m_arrObjIni[1] := stObjBelt.rX;
            m_arrObjIni[2] := stObjBelt.rY;
            m_arrObjIni[3] := stObjBelt.rZ;
            m_arrObjIni[4] := stObjBelt.rTh;
            m_stTrkOpt.SyncIn.ConveyorDistance := rSyncDist;
            m_bTrkExec := TRUE;     (* Held for the whole session *)
            m_bTrkSess := TRUE;
            m_bTrkRel  := FALSE;
            m_bTrkArm  := TRUE;     (* PCS move waits for Active *)
            m_fbTrkTo(IN := FALSE);  (* Restart the session watchdog *)
        ELSE
            (* Session already open (depart leg): arm directly *)
            m_bTrkArm := TRUE;
        END_IF
    ELSE
        (* Static MCS move: closes the session when it completes
           (BufferMode Aborting on the linear move, documented way to
           end conveyor tracking - iCube release notes 2025-6). *)
        m_bMvExec := TRUE;
        IF m_bTrkSess THEN
            m_bTrkDrop := TRUE;     (* Session release after Done *)
        END_IF
    END_IF
END_IF
m_udiSeqPrev := udiSeq;

(* 6) Tracking session (native mode): transform + watchdog -------------------- *)
m_fbTrk(
    AxesGroup    := ioGrp,
    ConveyorBelt := ioBelt,
    Execute      := m_bTrkExec,
    ConveyorBeltOrigin      := m_arrCbOrg,
    InitialObjectPosition   := m_arrObjIni,
    CoordSystem  := MC_COORDSYS#PCS,            (* CONFIRM enum spelling *)
    BufferMode   := MC_BUFFER_MODE#Aborting,    (* CONFIRM enum spelling *)
    ExecutionMode:= MC_ExecutionMode#Immediately, (* CONFIRM: Yaskawa extension *)
    TrackOptions := m_stTrkOpt,                 (* CONFIRM: SyncIn.ConveyorDistance > 0 *)
    Done         => ,
    Busy         => m_bTrkBusy,
    Active       => m_bTrkActi,
    CommandAborted => m_bTrkAbort,
    Error        => m_bTrkErr,
    ErrorID      => m_uiTrkErr
);

IF m_bTrkErr AND m_bTrkSess THEN
    (* Session rejected (option missing / belt axis invalid / distance 0):
       fail the pending tracked move instead of firing it in the wrong frame. *)
    bErr := TRUE;
    uiErrId := UINT#201;        (* 201 = tracking session start failed *)
    m_bTrkArm := FALSE;
    m_bMvExec := FALSE;
    m_bTrkSess := FALSE;
    m_bTrkExec := FALSE;
    m_bTrkRel  := FALSE;
ELSIF m_bTrkSess AND (NOT m_bTrkActi) AND m_bTrkArm THEN
    (* Watchdog: Active must assert within 2 s of the session request *)
    m_fbTrkTo(IN := TRUE, PT := T#2S);
    IF m_fbTrkTo.Q THEN
        bErr := TRUE;
        uiErrId := UINT#202;    (* 202 = tracking session did not engage *)
        m_bTrkArm := FALSE;
        m_bTrkSess := FALSE;
        m_bTrkExec := FALSE;
        m_bTrkRel  := FALSE;
    END_IF
END_IF

(* 7) Move execution (PLCopen level-based Execute) --------------------------- *)
IF m_bTrkArm AND m_bTrkActi AND (NOT m_bMvExec) THEN
    (* Transform confirmed: fire the synchronized PCS move now *)
    m_bMvExec := TRUE;
    m_bTrkArm := FALSE;
END_IF

IF bTrkReq AND m_bTrkActi AND (eMv = ET_SP_MvKind#TrackAbs) THEN
    (* Tracked move in the product coordinate system: the firmware
       superimposes the belt motion on the commanded PCS path. *)
    m_fbLin(
        AxesGroup    := ioGrp,
        Execute      := m_bMvExec,
        X            := stTargetBelt.rX,
        Y            := stTargetBelt.rY,
        Z            := stTargetBelt.rZ,
        Velocity     := rVel,
        Acceleration := rAcc,
        Deceleration := rDec,
        CoordSystem  := MC_COORDSYS#PCS,            (* CONFIRM enum spelling *)
        BufferMode   := MC_BUFFER_MODE#Aborting,    (* CONFIRM enum spelling *)
        Done         => m_bLinDone,
        Busy         => m_bLinBusy,
        CommandAborted => m_bLinAbort,
        Error        => m_bLinErr,
        ErrorID      => m_uiLinErr
    );
ELSE
    (* Static MCS move (approach / place / depart in fallback mode /
       session-ending move): world coordinates as in v1.x. *)
    m_fbLin(
        AxesGroup    := ioGrp,
        Execute      := m_bMvExec,
        X            := stTarget.rX,
        Y            := stTarget.rY,
        Z            := stTarget.rZ,
        Velocity     := rVel,
        Acceleration := rAcc,
        Deceleration := rDec,
        CoordSystem  := MC_COORDSYS#MCS,            (* CONFIRM enum spelling *)
        BufferMode   := MC_BUFFER_MODE#Aborting,    (* CONFIRM enum spelling *)
        Done         => m_bLinDone,
        Busy         => m_bLinBusy,
        CommandAborted => m_bLinAbort,
        Error        => m_bLinErr,
        ErrorID      => m_uiLinErr
    );
END_IF

IF m_bMvExec THEN
    bBusy := m_bLinBusy OR (NOT m_bLinDone);
    IF m_bLinErr OR m_bLinAbort THEN
        bErr     := TRUE;
        uiErrId  := m_uiLinErr;
        m_bMvExec := FALSE;
        bBusy := FALSE;
        IF m_bTrkDrop THEN
            (* Closing move failed: release the session anyway (safe state) *)
            m_bTrkDrop := FALSE;
            m_bTrkSess := FALSE;
            m_bTrkExec := FALSE;
            m_bTrkRel  := TRUE;
        END_IF
    ELSIF m_bLinDone THEN
        bDone := TRUE;
        m_bMvExec := FALSE;
        bBusy := FALSE;
        IF m_bTrkDrop THEN
            (* Static move finished: drop the belt transform now *)
            m_bTrkDrop := FALSE;
            m_bTrkSess := FALSE;
            m_bTrkExec := FALSE;
            m_bTrkRel  := TRUE;
        END_IF
    END_IF
ELSE
    bBusy := FALSE;
END_IF

(* 8) Session release bookkeeping -------------------------------------------- *)
IF m_bTrkRel AND (NOT m_bTrkActi) AND (NOT m_bTrkBusy) THEN
    m_bTrkRel := FALSE;     (* Transform fully dropped *)
END_IF
bTrkSess  := m_bTrkSess OR m_bTrkRel;
bTrkInSync := m_bTrkActi AND (NOT m_bTrkErr);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: SimBody (parent SP_RobMotion) - internal
   Self-contained kinematic simulation: enables instantly, interpolates
   the pose toward the target at the commanded velocity, pulses Done on
   arrival. No firmware calls (offline testability). The tracking session
   outputs are mirrored for HMI/debug so the same screens work offline.
   ----------------------------------------------------------------------- *)
METHOD SimBody : BOOL
VAR
    (* Path deltas and 3D length for simulated travel *)
    rDX, rDY, rDZ, rD : LREAL;
END_VAR
    SimBody := TRUE;                (* Simulated body stepped *)
    bEnabled := bEnable;
    bHomed   := bEnable;

    IF bStopReq THEN
        bBusy := FALSE;
        m_udiSeqPrev := udiSeq;
        m_bTrkSess := FALSE;
        m_bTrkArm  := FALSE;
        bTrkSess   := FALSE;
        bTrkInSync := FALSE;
        p2Now := m_p2Sim;
        rZNow := m_rZSim;
        RETURN;
    END_IF

    (* New request? *)
    IF (udiSeq <> m_udiSeqPrev) AND (eMv <> ET_SP_MvKind#None) AND (NOT bBusy) THEN
        bBusy := TRUE;
        (* Mirror the native session semantics: open on TrackAbs,
           closed by the next static move. *)
        IF eMv = ET_SP_MvKind#TrackAbs THEN
            m_bTrkSess := TRUE;
        ELSE
            m_bTrkSess := FALSE;
        END_IF
    END_IF

    IF bBusy THEN
        rDX := stTarget.rX - m_p2Sim.rX;
        rDY := stTarget.rY - m_p2Sim.rY;
        rDZ := stTarget.rZ - m_rZSim;
        rD  := SQRT(rDX*rDX + rDY*rDY + rDZ*rDZ);

        IF rD <= (rVel * m_rDtSec) THEN
            (* Arrival *)
            m_p2Sim.rX  := stTarget.rX;
            m_p2Sim.rY  := stTarget.rY;
            m_p2Sim.rTh := stTarget.rTh;
            m_rZSim := stTarget.rZ;
            bBusy := FALSE;
            bDone := TRUE;
        ELSIF rD > 1.0E-9 THEN
            m_p2Sim.rX  := m_p2Sim.rX + rDX / rD * (rVel * m_rDtSec);
            m_p2Sim.rY  := m_p2Sim.rY + rDY / rD * (rVel * m_rDtSec);
            m_rZSim     := m_rZSim + rDZ / rD * (rVel * m_rDtSec);
            m_p2Sim.rTh := stTarget.rTh;
        END_IF
    END_IF

    m_udiSeqPrev := udiSeq;
    p2Now := m_p2Sim;
    rZNow := m_rZSim;
    bTrkSess   := m_bTrkSess;
    bTrkInSync := m_bTrkSess AND bBusy;
END_METHOD
