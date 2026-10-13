(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 08_Robot
   Worksheet : FB - SP_Robot
   -----------------------------------------------------------------------------
   Purpose   : Per-robot pick & place executor (MotoPick 4 parity):

     - 3-point motion: approach / point / depart per feed x type with
       arbitrary path offsets, segment specific velocity and multiple
       precision modes (Exact / ZoneTight / ZoneWide).
     - Multi-gripping: asynchronous (cup by cup) and synchronous (single
       aligned move) pick and place of up to GC_CUPS parts per cycle.
     - Grip duration and advance timing (cut-off margin per tool).
     - Processing verification: pick verification (feedback), place
       verification, deferred verification, retry with cycle restart.
     - Pause/resume WITHOUT losing item or conveyor tracking: the job
       freezes in place, reservations stay owned, resume continues.
     - Trial run (dry run): motion preview with inhibited tool outputs.
     - Failure resiliency hooks: MarkFault/ClearFault for the System.

   Job protocol (System single-writer):
     1. System builds a job (reservations + targets) and calls OfferJob.
     2. Robot executes; on completion bJobDone pulses and m_stJobRes
        carries the per-item result flags (bPicked/bPlaced/bNg).
     3. System closes the queue records (CompletePick/PlaceTarget).
   Motion FW calls live in SP_RobMotion and are made ONLY from the body
   (it exposes VAR_IN_OUT; methods never touch it, per constraints).
   =============================================================================
*)

FUNCTION_BLOCK SP_Robot
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bSysRun : BOOL;             (* System running (production allowed) *)
    bSim    : BOOL;             (* Simulated kinematics *)
    uiDtMs  : UDINT;            (* Task period [ms] *)
    (* FW-2 group status pass-through (GVL_SP_Fw injection mode) *)
    bFwReady : BOOL;            (* Real group ready status *)
    bFwRef   : BOOL;            (* Real group referenced status *)
    (* R-05 zone guard: TRUE = free to move (granted or unguarded) *)
    bZoneOk  : BOOL := TRUE;    (* FALSE freezes the active job (zone hold) *)
    (* R-05b collision guard: live velocity scale [0.1..1], 1.0 = full speed *)
    rVelScale : LREAL := 1.0;
    stCmd   : ST_SP_RobCmd;     (* Public command struct (System/HMI writes) *)
END_VAR
VAR_IN_OUT
    ioGrp : AXES_GROUP_REF;     (* Firmware kinematic group *)
    ioaBelt: ARRAY[1..8] OF AXIS_REF; (* FW-1: belt encoder axes, one per feed (native tracking) 1..GC_FEEDS *)
END_VAR
VAR_OUTPUT
    stOut : ST_SP_RobStat;      (* Published status (HMI + balancer) *)
    bJobDone : BOOL;            (* One-cycle pulse: job finished *)
    m_stJobRes : ST_SP_Job;     (* Result copy (System reads after bJobDone) *)
    stCfg   : ST_SP_RobCfg;     (* Configuration *)
END_VAR
VAR
    m_iRob  : SINT := 1;
    (* TRUE after a valid Configure() *)
    m_bCfgOk: BOOL;
    (* Subordinate FBs *)
    m_Mot  : SP_RobMotion;      (* Motion adapter (body-called only) *)
    m_Tool : SP_ToolCtl;        (* Tool sequencer *)
    (* Job state *)
    m_stJob   : ST_SP_Job;
    (* TRUE while a job is admitted and not finished *)
    m_bJobVld : BOOL;
    (* Current job item index (1-based) *)
    m_iItem   : SINT := 1;
    (* Verification retry counter for the current pick *)
    m_uiRetry : UINT := 0;
    m_bPickNg : BOOL;           (* Current pick ended NG *)
    m_bPlaceNg: BOOL;           (* Current place ended NG *)
    (* Motion request interface *)
    m_udiMvSeq : UDINT := 0;
    (* Kind of the armed motion (None/approach/depart/...) *)
    m_eMv    : ET_SP_MvKind := ET_SP_MvKind#None;
    (* Armed motion target pose *)
    m_stTarget : ST_SP_Pose3D;
    (* Armed motion speed [mm/s] *)
    m_rVel  : LREAL := 500.0;
    (* Armed motion corner radius [mm] *)
    m_rZone : LREAL := 0.0;
    (* Segment targets *)
    m_stOff : ST_SP_PathOff;
    (* Computed approach pose (3-point path) *)
    m_stApp : ST_SP_Pose3D;
    (* Computed pick/place pose (3-point path) *)
    m_stPt  : ST_SP_Pose3D;
    (* Computed depart pose (3-point path) *)
    m_stDep : ST_SP_Pose3D;
    (* FSM *)
    m_eSt : ET_SP_RobState := ET_SP_RobState#Init;
    (* State of the previous cycle (edge detection) *)
    m_eStPrev : ET_SP_RobState := ET_SP_RobState#Init;
    (* State saved when the operator paused the robot *)
    m_eStPaused : ET_SP_RobState := ET_SP_RobState#Init;
    m_bEnter : BOOL;            (* TRUE on state entry cycle *)
    m_bPauseReq : BOOL;
    (* Resume request latch from the HMI *)
    m_bResumeReq: BOOL;
    m_bZoneHold : BOOL;         (* Frozen by the zone guard (auto-resume) *)
    m_bFault : BOOL;
    (* Dry-run mode: motions simulated, I/O inhibited *)
    m_bDryRun : BOOL;
    (* Homing command latch *)
    m_bCmdHome : BOOL;
    (* Stop command latch (GroupStop) *)
    m_bCmdStop : BOOL;
    (* Reset command latch *)
    m_bCmdReset: BOOL;
    (* Tool supervision *)
    m_iTool : SINT := 1;        (* Active tool of the current item *)
    m_uiToolTo: UDINT := 0;     (* Grip/release watchdog [ms] *)
    (* Bookkeeping *)
    m_bPicking : BOOL;
    (* Completed pick cycles (lifetime) *)
    m_uiCycles : UDINT := 0;
    (* Current fault code (0 = healthy) *)
    m_uiErrId  : UINT := 0;
    (* ---------------- R-07 synchronized multi-grip runtime -------------- *)
    (* TRUE while the job runs as one synchronized cluster descent *)
    m_bSync : BOOL;
    (* TRUE while a single failed cup is being re-gripped individually *)
    m_bRegrip : BOOL;
    (* TRUE when GripEval must freeze the per-cup picture (one-shot arm,
       prevents a stale re-freeze after each individual re-grip) *)
    m_bEvalArm : BOOL;
    (* Per-cup grip result of the synchronized descent (job item order) *)
    m_abCupOk : ARRAY[1..4] OF BOOL; (* 1..GC_CUPS *)
    (* Per-cup retry counters (synchronized pick AND place phases) *)
    m_auiCupRetry : ARRAY[1..4] OF UINT; (* 1..GC_CUPS *)
    (* TRUE while the synchronized place leg is executing *)
    m_bSyncPlaceRun : BOOL;
    (* TRUE after the synchronized place attempt (never retried as sync) *)
    m_bSyncPlaceDone : BOOL;
    (* Result of the last synchronized place geometry fit *)
    m_bSyncPlaceOk : BOOL;
    (* ---------------- FW-1 native conveyor tracking -------------------- *)
    (* Per-feed belt frame data (built by SetBeltFrames from the feed cfg) *)
    m_astBelt : ARRAY[1..8] OF ST_SP_BeltFrame; (* 1..GC_FEEDS *)
    (* TRUE when the armed tracked move runs native (mode on AND feed wired,
       plus the per-feed place selector on the place side, v1.4) *)
    m_bTrkReq : BOOL;
    (* v1.4: TRUE = the current place item runs the native tracked place
       (session on the outfeed belt). Set by CompPlaceTargets, cleared by
       the synchronized place path (cluster place stays static by design). *)
    m_bTrkPl : BOOL;
    (* Belt CS origin passed to the adapter session (world/MCS) *)
    m_stBeltOrg : ST_SP_Pose3D;
    (* Product pose in the belt CS at capture (session anchor) *)
    m_stObjBelt : ST_SP_Pose3D;
    (* Sync-in conveyor distance passed to the session [mm] *)
    m_rSyncDist : LREAL;
    (* Pick feed of the current item (belt axis index, always in range) *)
    m_iFeedNow : SINT := 1;
    (* Belt-frame (PCS) target of the armed tracked move *)
    m_stTargetBelt : ST_SP_Pose3D;
    (* Belt-frame pick point (mirror of m_stPt) *)
    m_stPtBelt : ST_SP_Pose3D;
    (* Belt-frame depart point (mirror of m_stDep) *)
    m_stDepBelt : ST_SP_Pose3D;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bJobDone := FALSE;

(* 0) Configuration gate --------------------------------------------------- *)
IF NOT m_bCfgOk THEN
    stOut.eState := ET_SP_RobState#Init;
    RETURN;
END_IF

(* 1) Command latch --------------------------------------------------------- *)
THIS.LatchCmds();

(* 2) Subordinate bodies (motion adapter called HERE ONLY) ------------------- *)
m_Mot(
    bSim := bSim,
    bEnable := bSysRun AND (NOT m_bFault),
    bStopReq := m_bCmdStop OR m_bPauseReq OR m_bFault,
    bReset := m_bCmdReset,
    uiDtMs := uiDtMs,
    udiSeq := m_udiMvSeq,
    eMv := m_eMv,
    stTarget := m_stTarget,
    rVel := m_rVel * rVelScale,     (* R-05b: live velocity scale from the collision guard. With the persistent Execute pattern the
                                       scaled velocity reaches the FW FB every cycle; on the iC9200 target prefer the group
                                       velocity override FB wired here (CONFIRM, see FW patch doc, section 3). *)
    rAcc := stCfg.rAcc,
    rDec := stCfg.rDec,
    rZone := m_rZone,
    rBeltSpd := 0.0,
    (* FW-1 native tracking session data (consumed when the armed move is
       a native tracked move; fallback mode ignores them) *)
    stTargetBelt := m_stTargetBelt,
    stBeltOrg := m_stBeltOrg,
    stObjBelt := m_stObjBelt,
    rSyncDist := m_rSyncDist,
    bTrkReq := m_bTrkReq,
    bFwReadyIn := bFwReady,
    bFwRefIn := bFwRef,
    ioGrp := ioGrp,
    ioBelt := ioaBelt[m_iFeedNow],
    bEnabled => ,
    bHomed => ,
    bBusy => ,
    bDone => ,
    bErr => ,
    uiErrId => ,
    p2Now => ,
    rZNow =>
);

m_Tool(
    bInhibit := m_bDryRun,
    uiDtMs := uiDtMs
);

(* 3) Pause / resume / zone hold ------------------------------------------- *)
(* R-05: the zone guard freezes the ACTIVE job only (same semantics as a
   pause: reservations stay owned, tracking is not lost). The release is
   automatic when the zone is granted again - no operator action. *)
IF (NOT bZoneOk) AND (m_eSt <> ET_SP_RobState#Paused)
   AND (m_eSt <> ET_SP_RobState#Fault) AND (m_eSt <> ET_SP_RobState#Init)
   AND (m_eSt <> ET_SP_RobState#WaitJob) THEN
    m_bZoneHold := TRUE;
    m_eStPaused := m_eSt;
    m_eSt := ET_SP_RobState#Paused;
ELSIF m_bZoneHold AND bZoneOk AND (m_eSt = ET_SP_RobState#Paused) THEN
    m_bZoneHold := FALSE;
    m_eSt := m_eStPaused;       (* Zone granted: continue the frozen step *)
ELSIF m_bPauseReq AND (m_eSt <> ET_SP_RobState#Paused)
  AND (m_eSt <> ET_SP_RobState#Fault) THEN
    m_bZoneHold := FALSE;       (* Operator pause overrides the zone hold *)
    m_eStPaused := m_eSt;
    m_eSt := ET_SP_RobState#Paused;
ELSIF m_bResumeReq AND (m_eSt = ET_SP_RobState#Paused) AND (NOT m_bZoneHold) THEN
    m_eSt := m_eStPaused;       (* Resume: continue the frozen step *)
END_IF

(* 4) Motion error ------------------------------------------------------------ *)
IF m_Mot.bErr AND (m_eSt <> ET_SP_RobState#Fault) THEN
    THIS.EnterFault(UINT#1);
END_IF

(* 5) Main FSM ----------------------------------------------------------------- *)
m_bEnter := (m_eSt <> m_eStPrev);
THIS.Fsm();
m_eStPrev := m_eSt;

(* 6) Publish status ------------------------------------------------------------ *)
THIS.Publish();
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_Robot)
   Validate configuration and bind subordinates.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Configuration to validate and store *)
    stIn   : ST_SP_RobCfg;
    (* Robot id bound to this instance (1..GC_ROBOTS) *)
    iRobot : SINT;
END_VAR
VAR
    (* Subordinate Configure() result accumulator *)
    eRc : ET_SP_RetCode;
END_VAR
    Configure := ET_SP_RetCode#Done;
    IF (iRobot < 1) OR (iRobot > GC_ROBOTS) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF (stIn.uiNumTools < 1)
       OR (stIn.uiNumTools > UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS))) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF (stIn.uiMaxGrip < 1)
       OR (stIn.uiMaxGrip > UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF

    stCfg  := stIn;
    m_iRob := iRobot;
    m_bCfgOk := TRUE;

    eRc := m_Tool.Configure(stIn.astTools, iRobot);
    IF eRc <> ET_SP_RetCode#Done THEN
        Configure := eRc;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OfferJob (parent SP_Robot)
   Job admission: accepted only when idle (WaitJob) and no fault.
   ----------------------------------------------------------------------- *)
METHOD OfferJob : BOOL
VAR_INPUT
    (* Job offered by the System *)
    stJob : ST_SP_Job;
END_VAR
VAR
    (* Per-cup reset loop index (R-07) *)
    i : SINT;
END_VAR
    OfferJob := FALSE;
    IF m_bFault OR m_bJobVld THEN
        RETURN;
    END_IF
    IF (m_eSt <> ET_SP_RobState#WaitJob) AND (m_eSt <> ET_SP_RobState#Ready) THEN
        RETURN;
    END_IF
    IF (stJob.uiCount < UINT#1) OR (stJob.uiCount > stCfg.uiMaxGrip) THEN
        RETURN;                     (* Empty job or exceeds multi-grip *)
    END_IF

    m_stJob := stJob;
    m_bJobVld := TRUE;
    m_iItem := 1;
    m_uiRetry := 0;
    m_bPickNg := FALSE;
    m_bPlaceNg := FALSE;
    (* R-07: synchronized execution only for multi-item SyncAll jobs *)
    m_bSync := (stJob.eExec = ET_SP_GripExec#SyncAll) AND (stJob.uiCount >= UINT#2);
    m_bRegrip := FALSE;
    m_bEvalArm := FALSE;
    m_bSyncPlaceRun := FALSE;
    m_bSyncPlaceDone := FALSE;
    m_bSyncPlaceOk := FALSE;
    FOR i := 1 TO GC_CUPS DO
        m_abCupOk[i] := FALSE;
        m_auiCupRetry[i] := UINT#0;
    END_FOR
    m_eSt := ET_SP_RobState#PlanPick;
    OfferJob := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CancelJob (parent SP_Robot)
   Drop the current job (System resets queues afterwards).
   ----------------------------------------------------------------------- *)
METHOD CancelJob : BOOL
VAR
    (* Cup loop index (sync state reset) *)
    i : SINT;
END_VAR
    CancelJob := TRUE;              (* Job dropped *)
    m_bJobVld := FALSE;
    m_bRegrip := FALSE;
    m_bSyncPlaceRun := FALSE;
    m_bSyncPlaceDone := FALSE;
    FOR i := 1 TO GC_CUPS DO
        m_abCupOk[i] := FALSE;
        m_auiCupRetry[i] := UINT#0;
    END_FOR
    IF (m_eSt <> ET_SP_RobState#Fault) AND (m_eSt <> ET_SP_RobState#Paused) THEN
        m_eSt := ET_SP_RobState#WaitJob;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: MarkFault (parent SP_Robot)
   Resiliency entry: System declares the robot down (group fault, axis
   alarm). Tools aborted, balancer exclusion via stOut.bFault.
   ----------------------------------------------------------------------- *)
METHOD MarkFault : BOOL
VAR
    (* Fixed alarm id for externally declared faults *)
    uiId : UINT := UINT#10;
END_VAR
    MarkFault := TRUE;              (* Fault entered *)
    THIS.EnterFault(uiId);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearFault (parent SP_Robot)
   Resiliency exit after the operator/System resolved the cause.
   ----------------------------------------------------------------------- *)
METHOD ClearFault : BOOL
VAR
    (* Cup loop index (sync state reset) *)
    i : SINT;
END_VAR
    ClearFault := TRUE;             (* Fault cleared *)
    m_bFault := FALSE;
    m_uiErrId := UINT#0;
    m_bJobVld := FALSE;
    m_bRegrip := FALSE;
    m_bSyncPlaceRun := FALSE;
    m_bSyncPlaceDone := FALSE;
    FOR i := 1 TO GC_CUPS DO
        m_abCupOk[i] := FALSE;
        m_auiCupRetry[i] := UINT#0;
    END_FOR
    m_eSt := ET_SP_RobState#WaitJob;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: EnterFault (parent SP_Robot) - internal
   ----------------------------------------------------------------------- *)
METHOD EnterFault : BOOL
VAR_INPUT
    (* Fixed alarm id for externally declared faults *)
    uiId : UINT;
END_VAR
    EnterFault := TRUE;             (* Fault state latched *)
    m_bFault := TRUE;
    m_uiErrId := uiId;
    m_eSt := ET_SP_RobState#Fault;
    m_Tool.AbortAll();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SetBeltFrames (parent SP_Robot) - FW-1 native tracking
   Build the per-feed belt frame data from the feed configurations.
   Called once by PRG_SP_TaskFast during setup, BEFORE the first job.
   The belt CS follows the PLCopen Part 4 6.6 convention: origin at the
   feed frame origin (pick line center, belt surface height), x-axis
   pointing along the belt travel direction:
     rPhi = stWorld.rRot + iDir * 90 deg      (angles in DEGREES, v1.7.0)
   ----------------------------------------------------------------------- *)
METHOD SetBeltFrames : ET_SP_RetCode
VAR_INPUT
    (* Feed configurations (source frames, directions, window data) 1..GC_FEEDS *)
    astTrk : ARRAY[1..8] OF ST_SP_TrkCfg;
END_VAR
VAR
    (* Feed scan index *)
    i : SINT;
    (* Belt frame under construction *)
    stFr : ST_SP_BeltFrame;
END_VAR
    SetBeltFrames := ET_SP_RetCode#Done;
    FOR i := 1 TO GC_FEEDS DO
        stFr.bUsed := astTrk[i].bUsed;
        stFr.stWorld := astTrk[i].stWorld;
        stFr.iDir := astTrk[i].iDir;
        stFr.rOrgX := astTrk[i].stWorld.rDx;
        stFr.rOrgY := astTrk[i].stWorld.rDy;
        stFr.rOrgZ := astTrk[i].rZBelt;
        stFr.rZBelt := astTrk[i].rZBelt;
        (* Belt CS x-axis along travel: feed v-axis rotated by the travel
           sign (quarter turn in DEGREES per the units convention) *)
        stFr.rPhi := astTrk[i].stWorld.rRot
                     + SINT_TO_LREAL(astTrk[i].iDir) * GC_90;
        (* Sync-in distance: window start is the natural latch-in point;
           guarded > 0 (FW 2026.6 rejects 0 with error 9006) *)
        stFr.rSyncDist := astTrk[i].rWinStart;
        IF stFr.rSyncDist <= 0.0 THEN
            stFr.rSyncDist := 100.0;   (* Safe default sync-in distance [mm] *)
        END_IF
        m_astBelt[i] := stFr;
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompBeltTargets (parent SP_Robot) - internal, FW-1 native
   Compute the belt-frame (PCS) mirrors of the tracked targets and the
   MC_TrackConveyorBelt session data for the current pick item.
   Called at the end of CompPickTargets / CompSyncPickTargets.

   Geometry:
     - Item pose in the belt CS at CAPTURE (fixed, encoder-based):
         x = iDir * v   (v = rBeltCap, along-belt offset at capture)
         y = -iDir * u  (u = across-belt coordinate, inverse transform
                         of the stored world pose)
         z = rZWorld - rZBelt,  th = item yaw - belt CS rotation
     - The PCS is the PRODUCT frame (PLCopen 6.6: the product stands
       still in PCS, the firmware superimposes the belt travel). The
       tracked targets are therefore the ITEM-RELATIVE offsets expressed
       in the object frame: world delta rotated by the product world yaw.
       Z and yaw offsets are rotation-invariant.
     - The approach point stays in WORLD (static MCS entry move).
   ----------------------------------------------------------------------- *)
METHOD CompBeltTargets : BOOL
VAR_INPUT
    (* World base pose the targets were computed from (cup on item) *)
    stBase : ST_SP_Pose3D;
    (* Pick feed 1..GC_FEEDS *)
    iFeed  : SINT;
    (* Reserved item snapshot (capture data); v1.4 place side = target *)
    stItem : ST_SP_TrkItem;
    (* v1.4: TRUE = place side - the native policy additionally gates on
       the per-feed tracked place selector GVL_SP_Fw.g_abPlaceTrack *)
    bPlaceSel : BOOL;
END_VAR
VAR
    (* Clamped feed index *)
    iF : SINT;
    (* Belt frame of the pick feed *)
    stFr : ST_SP_BeltFrame;
    (* Item across-belt coordinate at capture [mm] *)
    rU : LREAL;
    (* cos / sin of the product world yaw (rotate into the object frame) *)
    rCos, rSin : LREAL;
    (* World-frame offsets from the base pose *)
    rDX, rDY : LREAL;
END_VAR
    CompBeltTargets := TRUE;        (* Session data + mirrors computed *)
    iF := iFeed;
    IF (iF < 1) OR (iF > GC_FEEDS) THEN
        iF := 1;
    END_IF
    m_iFeedNow := iF;
    stFr := m_astBelt[iF];

    IF NOT stFr.bUsed THEN
        (* Feed not wired for native tracking: keep the world targets as
           belt-frame copies; the adapter runs the fallback cut-off path. *)
        m_bTrkReq := FALSE;
        m_stPtBelt := m_stPt;
        m_stDepBelt := m_stDep;
        RETURN;
    END_IF

    (* Native policy gate: global mode is evaluated here so the adapter
       only receives per-move requests (bTrkReq). v1.4: the place side
       additionally requires the per-feed tracked place selector. *)
    m_bTrkReq := (GVL_SP_Fw.g_eTrkMode = 1);
    IF bPlaceSel AND (NOT GVL_SP_Fw.g_abPlaceTrack[iF]) THEN
        m_bTrkReq := FALSE;
    END_IF
    IF NOT m_bTrkReq THEN
        (* Static mode: keep the mirrors equal to the world targets so the
           belt-frame diagnostics stay meaningful in every mode *)
        m_stPtBelt := m_stPt;
        m_stDepBelt := m_stDep;
        RETURN;
    END_IF

    (* ---- Session data: belt CS origin in world/MCS ---- *)
    m_stBeltOrg.rX  := stFr.rOrgX;
    m_stBeltOrg.rY  := stFr.rOrgY;
    m_stBeltOrg.rZ  := stFr.rOrgZ;
    m_stBeltOrg.rTh := stFr.rPhi;

    (* ---- Session data: product pose in the belt CS at capture ---- *)
    rU := FUN_SP_InvTrfX(stFr.stWorld, stItem.p2World.rX, stItem.p2World.rY);
    m_stObjBelt.rX  := SINT_TO_LREAL(stFr.iDir) * stItem.rBeltCap;
    m_stObjBelt.rY  := -SINT_TO_LREAL(stFr.iDir) * rU;
    m_stObjBelt.rZ  := stItem.rZWorld - stFr.rZBelt;
    m_stObjBelt.rTh := FUN_SP_NormAng(stItem.p2World.rTh - stFr.rPhi);
    m_rSyncDist := stFr.rSyncDist;

    (* ---- Product-frame (PCS) mirrors of the tracked targets ---- *)
    (* The PCS origin IS the product: the commanded point is the plain
       item-relative offset in the object frame (rotation by the product
       world yaw), so the firmware keeps it glued to the product while
       the belt advances. *)
    rCos := COS(stBase.rTh * GC_DEG2RAD);   (* deg -> rad at the trig boundary *)
    rSin := SIN(stBase.rTh * GC_DEG2RAD);

    (* Pick point (m_stPt) *)
    rDX := m_stPt.rX - stBase.rX;
    rDY := m_stPt.rY - stBase.rY;
    m_stPtBelt.rX  :=  rCos * rDX + rSin * rDY;
    m_stPtBelt.rY  := -rSin * rDX + rCos * rDY;
    m_stPtBelt.rZ  := m_stPt.rZ - stBase.rZ;
    m_stPtBelt.rTh := FUN_SP_NormAng(m_stPt.rTh - stBase.rTh);

    (* Depart point (m_stDep): tracked lift-off follows the item *)
    rDX := m_stDep.rX - stBase.rX;
    rDY := m_stDep.rY - stBase.rY;
    m_stDepBelt.rX  :=  rCos * rDX + rSin * rDY;
    m_stDepBelt.rY  := -rSin * rDX + rCos * rDY;
    m_stDepBelt.rZ  := m_stDep.rZ - stBase.rZ;
    m_stDepBelt.rTh := FUN_SP_NormAng(m_stDep.rTh - stBase.rTh);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: MvToBelt (parent SP_Robot) - internal, FW-1 native
   Arm a belt-synchronized move: world target (fallback path) plus the
   belt-frame target (native PCS path). Fires as ET_SP_MvKind#TrackAbs.
   ----------------------------------------------------------------------- *)
METHOD MvToBelt : BOOL
VAR_INPUT
    (* World target (used by the fallback cut-off path) *)
    stT    : ST_SP_Pose3D;
    (* Belt-frame target (used by the native PCS path) *)
    stB    : ST_SP_Pose3D;
    (* Motion speed [mm/s] *)
    rVel   : LREAL;
    (* Positioning precision class *)
    ePrec  : ET_SP_Precision;
END_VAR
    MvToBelt := TRUE;               (* Belt move armed *)
    m_stTargetBelt := stB;
    THIS.MvTo(stT, ET_SP_MvKind#TrackAbs, rVel, ePrec);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: LatchCmds (parent SP_Robot) - internal
   One-cycle command latch from the public stCmd struct.
   ----------------------------------------------------------------------- *)
METHOD LatchCmds : BOOL
    LatchCmds := TRUE;              (* Commands latched *)
    m_bCmdHome  := stCmd.bHome;
    m_bCmdStop  := stCmd.bStop;
    m_bCmdReset := stCmd.bReset;
    m_bPauseReq := stCmd.bPause;
    m_bResumeReq:= stCmd.bResume;
    m_bDryRun   := stCmd.bDryRun;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: MvTo (parent SP_Robot) - internal
   Arm a motion request (the body fires it through SP_RobMotion).
   ----------------------------------------------------------------------- *)
METHOD MvTo : BOOL
VAR_INPUT
    (* Target pose of the motion *)
    stT    : ST_SP_Pose3D;
    (* Motion kind selector *)
    eKind  : ET_SP_MvKind;
    (* Motion speed [mm/s] *)
    rVel   : LREAL;
    (* Positioning precision class *)
    ePrec  : ET_SP_Precision;
END_VAR
    MvTo := TRUE;                   (* Motion request armed *)
    m_stTarget := stT;
    m_eMv := eKind;
    m_rVel := rVel;
    CASE ePrec OF
        ET_SP_Precision#Exact:     m_rZone := 0.0;
        ET_SP_Precision#ZoneTight: m_rZone := stCfg.rZoneTight;
        ET_SP_Precision#ZoneWide:  m_rZone := stCfg.rZoneWide;
    END_CASE
    m_udiMvSeq := m_udiMvSeq + 1;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CupPose (parent SP_Robot) - internal
   TCP pose to align one gripper cup with item pose: item pose minus cup
   offset rotated by item yaw.
   ----------------------------------------------------------------------- *)
METHOD CupPose : ST_SP_Pose3D
VAR_INPUT
    (* Item pose the cup is attached to *)
    p3    : ST_SP_Pose3D;
    (* Tool index (1-based) *)
    uiTool: UINT;
    (* Cup index inside the tool (1-based) *)
    uiCup : UINT;
END_VAR
VAR
    (* Cup offset from the tool frame *)
    stCup : ST_SP_Point3D;
    (* Result pose after offset rotation *)
    stRes : ST_SP_Pose3D;
END_VAR
    stCup.rX := 0.0;
    stCup.rY := 0.0;
    stCup.rZ := 0.0;
    IF (uiTool >= 1) AND (uiTool <= UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS))) THEN
        IF (uiCup >= 1) AND (uiCup <= UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
            stCup := stCfg.astTools[uiTool].astCups[uiCup];
        END_IF
    END_IF

    stRes.rX  := p3.rX - FUN_SP_RotX(p3.rTh, stCup.rX, stCup.rY);
    stRes.rY  := p3.rY - FUN_SP_RotY(p3.rTh, stCup.rX, stCup.rY);
    stRes.rZ  := p3.rZ - stCup.rZ;
    stRes.rTh := p3.rTh;
    CupPose := stRes;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: LoadOff (parent SP_Robot) - internal
   Fetch the 3-point path offsets for feed x type (exact index, fallback
   to type 1 entry when the specific type is not configured).
   ----------------------------------------------------------------------- *)
METHOD LoadOff : BOOL
VAR_INPUT
    (* Feed whose offset table is queried *)
    iFeed  : SINT;
    (* Product type (falls back to type 1 entry) *)
    uiType : UINT;
END_VAR
VAR
    (* Clamped feed and type table indices *)
    iF, iT : SINT;
END_VAR
    LoadOff := TRUE;                (* Offset table loaded *)
    iF := DINT_TO_SINT(FUN_SP_ClampI(SINT_TO_DINT(iFeed), 1, SINT_TO_DINT(GC_FEEDS)));
    iT := DINT_TO_SINT(FUN_SP_ClampI(UINT_TO_DINT(uiType), 1, SINT_TO_DINT(GC_TYPES)));
    m_stOff := stCfg.astOff[iF][iT];
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompPickTargets (parent SP_Robot) - internal
   Build approach / point / depart targets for the pick of item m_iItem.
   Dry run lifts the working Z by the safe height.
   ----------------------------------------------------------------------- *)
METHOD CompPickTargets : BOOL
VAR
    (* Current job item snapshot *)
    stJI : ST_SP_JobItem;
    (* Base pose (item or slot) of the current item *)
    stBase : ST_SP_Pose3D;
    (* Configured lift height above the base pose [mm] *)
    rLift : LREAL;
END_VAR
    CompPickTargets := TRUE;        (* Pick targets computed *)
    stJI := m_stJob.astItems[m_iItem];
    THIS.LoadOff(stJI.iFeedPick, stJI.stItem.uiTypeId);
    stBase := THIS.CupPose(stJI.p3Pick, stJI.uiTool, stJI.uiCup);

    rLift := m_stOff.rPtDz;
    IF m_bDryRun THEN
        rLift := rLift + stCfg.rZSafe;
    END_IF

    m_stPt.rX  := stBase.rX;
    m_stPt.rY  := stBase.rY;
    m_stPt.rZ  := stBase.rZ + rLift;
    m_stPt.rTh := stBase.rTh;

    m_stApp.rX  := stBase.rX + m_stOff.rAppDx;
    m_stApp.rY  := stBase.rY + m_stOff.rAppDy;
    m_stApp.rZ  := m_stPt.rZ + ABS(m_stOff.rAppDz);
    m_stApp.rTh := stBase.rTh;

    m_stDep.rX  := stBase.rX + m_stOff.rDepDx;
    m_stDep.rY  := stBase.rY + m_stOff.rDepDy;
    m_stDep.rZ  := m_stPt.rZ + ABS(m_stOff.rDepDz);
    m_stDep.rTh := stBase.rTh;

    (* FW-1: belt-frame mirrors + MC_TrackConveyorBelt session data *)
    THIS.CompBeltTargets(stBase, stJI.iFeedPick, stJI.stItem, FALSE);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompPlaceTargets (parent SP_Robot) - internal
   Build approach / point / depart targets for the place of item m_iItem.
   Dry run lifts the working Z by the safe height.
   v1.4: when the place feed is wired AND g_eTrkMode = 1 AND the per-feed
   tracked place selector is on, the method also arms the native tracked
   place (session data from the placement target capture snapshot +
   slot-relative PCS mirrors); m_bTrkPl carries the decision to the
   Place / Retreat states.
   ----------------------------------------------------------------------- *)
METHOD CompPlaceTargets : BOOL
VAR
    (* Current job item snapshot *)
    stJI : ST_SP_JobItem;
    (* Base pose (item or slot) of the current item *)
    stBase : ST_SP_Pose3D;
    (* Configured lift height above the base pose [mm] *)
    rLift : LREAL;
END_VAR
    CompPlaceTargets := TRUE;       (* Place targets computed *)
    stJI := m_stJob.astItems[m_iItem];
    THIS.LoadOff(stJI.iFeedPlace, stJI.stItem.uiTypeId);
    stBase := THIS.CupPose(stJI.p3Place, stJI.uiTool, stJI.uiCup);

    rLift := 0.0;
    IF m_bDryRun THEN
        rLift := stCfg.rZSafe;
    END_IF

    m_stPt.rX  := stBase.rX;
    m_stPt.rY  := stBase.rY;
    m_stPt.rZ  := stBase.rZ + rLift;
    m_stPt.rTh := stBase.rTh;

    m_stApp.rX  := stBase.rX + m_stOff.rAppDx;
    m_stApp.rY  := stBase.rY + m_stOff.rAppDy;
    m_stApp.rZ  := m_stPt.rZ + ABS(m_stOff.rAppDz);
    m_stApp.rTh := stBase.rTh;

    m_stDep.rX  := stBase.rX + m_stOff.rDepDx;
    m_stDep.rY  := stBase.rY + m_stOff.rDepDy;
    m_stDep.rZ  := m_stPt.rZ + ABS(m_stOff.rDepDz);
    m_stDep.rTh := stBase.rTh;

    (* FW-1 v1.4: native tracked place session data + slot-relative PCS
       mirrors (computed inside CompBeltTargets from the TARGET capture
       snapshot stTgt; the per-feed selector gates the request there). *)
    THIS.CompBeltTargets(stBase, stJI.iFeedPlace, stJI.stTgt, TRUE);
    m_bTrkPl := m_bTrkReq;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AdvancePickItem (parent SP_Robot) - internal
   Select the next job item that still needs its pick. TRUE when found
   (m_iItem updated).
   ----------------------------------------------------------------------- *)
METHOD AdvancePickItem : BOOL
VAR
    (* Job item scan index (pick) *)
    i : SINT;
END_VAR
    AdvancePickItem := FALSE;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPick
           AND (NOT m_stJob.astItems[i].bPicked)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            m_iItem := i;
            AdvancePickItem := TRUE;
            EXIT;
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AdvancePlaceItem (parent SP_Robot) - internal
   Select the next job item that still needs its place. TRUE when found.
   ----------------------------------------------------------------------- *)
METHOD AdvancePlaceItem : BOOL
VAR
    (* Job item scan index (place) *)
    i : SINT;
END_VAR
    AdvancePlaceItem := FALSE;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPlace
           AND m_stJob.astItems[i].bPicked
           AND (NOT m_stJob.astItems[i].bPlaced)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            m_iItem := i;
            AdvancePlaceItem := TRUE;
            EXIT;
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CloseJob (parent SP_Robot) - internal
   Publish the job results and return to idle.
   ----------------------------------------------------------------------- *)
METHOD CloseJob : BOOL
    CloseJob := TRUE;               (* Results published *)
    m_stJobRes := m_stJob;
    bJobDone := TRUE;           (* One-cycle pulse for the System *)
    m_bJobVld := FALSE;
    m_uiCycles := m_uiCycles + 1;
    m_eSt := ET_SP_RobState#WaitJob;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompSyncPickTargets (parent SP_Robot) - internal (R-07)
   Build approach / point / depart targets for the synchronized cluster
   descent. The cluster TCP pose comes with the job (SP_Dispatch); the
   3-point path offsets are taken from the anchor item (item 1).
   ----------------------------------------------------------------------- *)
METHOD CompSyncPickTargets : BOOL
VAR
    (* Anchor job item (offset source) *)
    stJI : ST_SP_JobItem;
    (* Configured lift height above the base pose [mm] *)
    rLift : LREAL;
    (* Cluster TCP pose reference *)
    stT : ST_SP_Pose3D;
END_VAR
    CompSyncPickTargets := TRUE;    (* Cluster pick targets computed *)
    stJI := m_stJob.astItems[1];
    THIS.LoadOff(stJI.iFeedPick, stJI.stItem.uiTypeId);
    stT := m_stJob.stSyncPick;

    rLift := m_stOff.rPtDz;
    IF m_bDryRun THEN
        rLift := rLift + stCfg.rZSafe;
    END_IF

    m_stPt.rX  := stT.rX;
    m_stPt.rY  := stT.rY;
    m_stPt.rZ  := stT.rZ + rLift;
    m_stPt.rTh := stT.rTh;

    m_stApp.rX  := stT.rX + m_stOff.rAppDx;
    m_stApp.rY  := stT.rY + m_stOff.rAppDy;
    m_stApp.rZ  := m_stPt.rZ + ABS(m_stOff.rAppDz);
    m_stApp.rTh := stT.rTh;

    m_stDep.rX  := stT.rX + m_stOff.rDepDx;
    m_stDep.rY  := stT.rY + m_stOff.rDepDy;
    m_stDep.rZ  := m_stPt.rZ + ABS(m_stOff.rDepDz);
    m_stDep.rTh := stT.rTh;

    (* FW-1: belt-frame mirrors + session data (anchor item 1) *)
    THIS.CompBeltTargets(stT, stJI.iFeedPick, stJI.stItem, FALSE);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompSyncPlaceTargets (parent SP_Robot) - internal (R-07)
   Try to build ONE synchronized place descent for all pending place
   targets: least-squares TCP fit over the target poses against the cup
   layout (same math as the pick cluster, no belt translation - targets
   are already cut-off predicted world poses). Sets m_bSyncPlaceOk and,
   on success, the approach/point/depart targets. Tolerance and cup
   layout come from the first pending item's tool.
   ----------------------------------------------------------------------- *)
METHOD CompSyncPlaceTargets : BOOL
VAR
    (* Job item scan index (place side) *)
    i  : SINT;
    (* Pending place item count and tool of the first one *)
    uiN : UINT;
    uiTool : UINT;                         (* Tool of the first pending place item (cup layout source) *)
    (* Member poses and reordered cup offsets (residual input) 1..GC_CUPS *)
    astP  : ARRAY[1..4] OF ST_SP_Pose3D;
    astCw : ARRAY[1..4] OF ST_SP_Point3D; (* World poses of the pending place points (LSQ fit input) *)
    (* Fitted TCP yaw / translation and worst residual *)
    rYaw, rTx, rTy, rRes : LREAL;
    (* Match tolerance from the tool configuration [mm] *)
    rTol : LREAL;
    (* Anchor job item (offset source) *)
    stJI : ST_SP_JobItem;
    (* Working place pose *)
    stT : ST_SP_Pose3D;
    (* Dry-run lift [mm] *)
    rLift : LREAL;
END_VAR
    CompSyncPlaceTargets := TRUE;   (* Executed; result in m_bSyncPlaceOk *)
    m_bSyncPlaceOk := FALSE;
    uiN := UINT#0;
    uiTool := UINT#1;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        stJI := m_stJob.astItems[i];
        IF stJI.bPlace AND (NOT stJI.bPlaced) AND (NOT stJI.bNg) THEN
            uiN := uiN + UINT#1;
            astP[uiN] := stJI.p3Place;
            IF uiN = UINT#1 THEN
                uiTool := stJI.uiTool;
            END_IF
            IF (stJI.uiTool >= UINT#1) AND (stJI.uiTool <= UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS)))
               AND (stJI.uiCup >= UINT#1) AND (stJI.uiCup <= UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
                astCw[uiN] := stCfg.astTools[stJI.uiTool].astCups[stJI.uiCup];
            ELSE
                astCw[uiN].rX := 0.0;
                astCw[uiN].rY := 0.0;
                astCw[uiN].rZ := 0.0;
            END_IF
        END_IF
    END_FOR
    IF uiN < UINT#2 THEN
        RETURN;                 (* Nothing to synchronize *)
    END_IF

    rTol := stCfg.astTools[uiTool].rMatchTol;
    IF rTol <= 0.0 THEN
        RETURN;                 (* Sync place not configured on this tool *)
    END_IF

    (* Least-squares fit (yaw = circular mean, XY = mean translation) *)
    rYaw := FUN_SP_FitYaw(astP, uiN);
    rTx := 0.0; rTy := 0.0;
    FOR i := 1 TO UINT_TO_SINT(uiN) DO
        rTx := rTx + astP[i].rX - FUN_SP_RotX(rYaw, astCw[i].rX, astCw[i].rY);
        rTy := rTy + astP[i].rY - FUN_SP_RotY(rYaw, astCw[i].rX, astCw[i].rY);
    END_FOR
    rTx := rTx / UDINT_TO_LREAL(UINT_TO_UDINT(uiN));
    rTy := rTy / UDINT_TO_LREAL(UINT_TO_UDINT(uiN));
    stT.rX  := rTx;
    stT.rY  := rTy;
    stT.rZ  := astP[1].rZ;
    stT.rTh := rYaw;

    rRes := FUN_SP_ClusterResidual(astP, astCw, stT, uiN);
    IF rRes > rTol THEN
        RETURN;                 (* Formation does not match the cup layout *)
    END_IF

    (* Accepted: build the 3-point targets from the fitted TCP pose *)
    m_bSyncPlaceOk := TRUE;
    (* v1.4: the synchronized place stays STATIC (cut-off prediction):
       the cluster targets may span two tray instances of the outfeed, so
       a single MC_TrackConveyorBelt session cannot represent them. Drop
       any stale tracked-place request before the cluster descent. *)
    m_bTrkPl := FALSE;
    m_bTrkReq := FALSE;
    THIS.LoadOff(m_stJob.astItems[m_iItem].iFeedPlace,
                 m_stJob.astItems[m_iItem].stItem.uiTypeId);
    rLift := 0.0;
    IF m_bDryRun THEN
        rLift := stCfg.rZSafe;
    END_IF

    m_stPt.rX  := stT.rX;
    m_stPt.rY  := stT.rY;
    m_stPt.rZ  := stT.rZ + rLift;
    m_stPt.rTh := stT.rTh;

    m_stApp.rX  := stT.rX + m_stOff.rAppDx;
    m_stApp.rY  := stT.rY + m_stOff.rAppDy;
    m_stApp.rZ  := m_stPt.rZ + ABS(m_stOff.rAppDz);
    m_stApp.rTh := stT.rTh;

    m_stDep.rX  := stT.rX + m_stOff.rDepDx;
    m_stDep.rY  := stT.rY + m_stOff.rDepDy;
    m_stDep.rZ  := m_stPt.rZ + ABS(m_stOff.rDepDz);
    m_stDep.rTh := stT.rTh;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SyncPickPending (parent SP_Robot) - internal (R-07)
   TRUE when the synchronized job still has a pick to execute (the whole
   cluster is picked in one descent, so this is checked as a set).
   ----------------------------------------------------------------------- *)
METHOD SyncPickPending : BOOL
VAR
    (* Job item scan index (pick side) *)
    i : SINT;
END_VAR
    SyncPickPending := FALSE;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPick
           AND (NOT m_stJob.astItems[i].bPicked)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            SyncPickPending := TRUE;
            RETURN;
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SyncPlaceTry (parent SP_Robot) - internal (R-07)
   Gate for the synchronized place: TRUE when all picks are closed, at
   least two place targets are pending, the one-shot policy allows the
   attempt and the geometry fit accepted the formation. On acceptance the
   3-point targets are already armed (CompSyncPlaceTargets).
   ----------------------------------------------------------------------- *)
METHOD SyncPlaceTry : BOOL
VAR
    (* Job item scan index (place side) *)
    i  : SINT;
    (* Pending place item counter *)
    uiN : UINT;
    (* Cup loop index (place retry reset) *)
    k  : SINT;
END_VAR
    SyncPlaceTry := FALSE;
    IF NOT m_bSync THEN
        RETURN;
    END_IF
    IF m_bSyncPlaceRun OR m_bSyncPlaceDone THEN
        RETURN;                 (* Attempt already running or consumed *)
    END_IF

    (* Every pick side must be closed (picked or NG) before placing *)
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPick
           AND (NOT m_stJob.astItems[i].bPicked)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            RETURN;             (* Pick half not complete yet *)
        END_IF
    END_FOR

    (* Count the pending place targets *)
    uiN := UINT#0;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPlace
           AND (NOT m_stJob.astItems[i].bPlaced)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            uiN := uiN + UINT#1;
        END_IF
    END_FOR
    IF uiN < UINT#2 THEN
        RETURN;                 (* Individual place path handles the rest *)
    END_IF

    (* Geometry fit + target arming *)
    THIS.CompSyncPlaceTargets();
    IF NOT m_bSyncPlaceOk THEN
        m_bSyncPlaceDone := TRUE;   (* Never re-try the sync attempt *)
        RETURN;
    END_IF

    (* Fresh per-cup retry budget for the place phase *)
    FOR k := 1 TO GC_CUPS DO
        m_auiCupRetry[k] := UINT#0;
    END_FOR
    m_bSyncPlaceRun := TRUE;
    SyncPlaceTry := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CupHolding (parent SP_Robot) - internal (R-07)
   TRUE when the cup currently holds a part (per-cup vacuum feedback
   when configured, tool feedback otherwise).
   ----------------------------------------------------------------------- *)
METHOD CupHolding : BOOL
VAR_INPUT
    (* Cup index inside the active tool (1-based) *)
    iCup : SINT;
END_VAR
    CupHolding := m_Tool.FbkCup(m_iTool, iCup);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Fsm (parent SP_Robot) - internal
   Main pick & place state machine. All firmware interaction happens in
   the body through SP_RobMotion / SP_ToolCtl.
   Error codes: 1 = motion error, 2 = grip watchdog, 3 = place watchdog.
   ----------------------------------------------------------------------- *)
METHOD Fsm : BOOL
VAR
    (* Job item being closed *)
    stJI : ST_SP_JobItem;
    (* Result of the pick/place completion call *)
    bOk  : BOOL;
    (* Job item scan index (R-07 per-cup evaluation) *)
    i    : SINT;
END_VAR
    Fsm := TRUE;                    (* FSM step executed *)
    CASE m_eSt OF

        ET_SP_RobState#Init:
            IF bSysRun THEN
                m_eSt := ET_SP_RobState#Homing;
            END_IF

        ET_SP_RobState#Homing:
            (* Group readiness consumed from the adapter (CONFIRM binding) *)
            IF m_Mot.bHomed THEN
                m_eSt := ET_SP_RobState#Ready;
            END_IF

        ET_SP_RobState#Ready:
            m_eSt := ET_SP_RobState#WaitJob;

        ET_SP_RobState#WaitJob:
            IF m_bJobVld THEN
                m_eSt := ET_SP_RobState#PlanPick;
            END_IF

        (* ------------------------------ PICK ---------------------------- *)
        ET_SP_RobState#PlanPick:
            IF NOT m_bJobVld THEN
                m_eSt := ET_SP_RobState#WaitJob;
            ELSIF m_bSync AND THIS.SyncPickPending() THEN
                (* R-07: the whole cluster is picked in ONE descent *)
                THIS.CompSyncPickTargets();
                m_bPicking := TRUE;
                m_eSt := ET_SP_RobState#MoveApp;
            ELSIF THIS.AdvancePickItem() THEN
                THIS.CompPickTargets();
                m_bPicking := TRUE;
                m_eSt := ET_SP_RobState#MoveApp;
            ELSE
                (* Pick side complete: proceed to the place half *)
                m_eSt := ET_SP_RobState#PlanPlace;
            END_IF

        ET_SP_RobState#MoveApp:
            IF m_bEnter THEN
                stJI := m_stJob.astItems[m_iItem];
                m_iTool := UINT_TO_SINT(stJI.uiTool);
                THIS.MvTo(m_stApp, ET_SP_MvKind#LinearAbs,
                          stCfg.rVelApp, stCfg.ePrecApp);
            ELSIF m_Mot.bDone THEN
                m_eSt := ET_SP_RobState#TrackPick;
            END_IF

        ET_SP_RobState#TrackPick:
            IF m_bEnter THEN
                (* FW-1: tracked move carries both targets; the adapter
                   picks the PCS path when native tracking is active *)
                THIS.MvToBelt(m_stPt, m_stPtBelt,
                              stCfg.rVelTrack, stCfg.ePrecPick);
            ELSIF m_Mot.bDone THEN
                m_uiToolTo := UDINT#0;
                m_eSt := ET_SP_RobState#Grip;
            END_IF

        ET_SP_RobState#Grip:
            IF m_bEnter THEN
                IF m_bSync AND (NOT m_bRegrip) THEN
                    (* R-07: whole-head synchronized grip with per-cup capture *)
                    bOk := m_Tool.GripSync(m_iTool, m_stJob.uiCount) = ET_SP_RetCode#Done;
                ELSE
                    bOk := m_Tool.GripStart(m_iTool) = ET_SP_RetCode#Done;
                END_IF
                IF NOT bOk THEN
                    THIS.EnterFault(UINT#2);
                END_IF
            ELSE
                m_uiToolTo := m_uiToolTo + uiDtMs;
                IF m_Tool.bDone THEN
                    IF m_bSync AND (NOT m_bRegrip) THEN
                        (* Cluster descent finished: evaluate cup by cup *)
                        m_bEvalArm := TRUE;
                        m_eSt := ET_SP_RobState#GripEval;
                    ELSIF m_bRegrip THEN
                        (* R-07: single re-grip of one failed cup finished *)
                        stJI := m_stJob.astItems[m_iItem];
                        m_bRegrip := FALSE;
                        IF stCfg.bVerifyPick AND (NOT m_bDryRun)
                           AND (NOT THIS.CupHolding(UINT_TO_SINT(stJI.uiCup))) THEN
                            m_eSt := ET_SP_RobState#GripEval;  (* Eval decides *)
                        ELSE
                            m_stJob.astItems[m_iItem].bPicked := TRUE;
                            m_abCupOk[m_iItem] := TRUE;
                            m_eSt := ET_SP_RobState#GripEval;
                        END_IF
                    ELSE
                        stJI := m_stJob.astItems[m_iItem];
                        IF stCfg.bVerifyPick AND (NOT m_bDryRun)
                           AND (NOT THIS.CupHolding(UINT_TO_SINT(stJI.uiCup))) THEN
                            (* Pick verification failed: retry policy *)
                            m_uiRetry := m_uiRetry + 1;
                            IF m_uiRetry <= stCfg.uiRetries THEN
                                m_eSt := ET_SP_RobState#TrackPick;  (* Cycle restart *)
                            ELSE
                                m_stJob.astItems[m_iItem].bNg := TRUE;
                                m_bPickNg := TRUE;
                                m_uiRetry := 0;
                                m_eSt := ET_SP_RobState#Depart;
                            END_IF
                        ELSE
                            m_stJob.astItems[m_iItem].bPicked := TRUE;
                            m_uiRetry := 0;
                            m_eSt := ET_SP_RobState#Depart;
                        END_IF
                    END_IF
                ELSIF m_uiToolTo > (TIME_TO_UDINT(stCfg.astTools[m_iTool].tGrip) + UDINT#2000) THEN
                    THIS.EnterFault(UINT#2);    (* Grip watchdog *)
                END_IF
            END_IF

        ET_SP_RobState#GripEval:
            (* R-07 synchronized multi-grip evaluation: freeze the per-cup
               picture ONCE per synchronized grip (armed by the Grip state,
               NOT re-frozen after individual re-grips), then loop re-grips
               over the failed cups until every cup is confirmed or its
               retries are exhausted. *)
            IF m_bEnter AND m_bEvalArm THEN
                m_bEvalArm := FALSE;
                FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
                    IF stCfg.bVerifyPick AND (NOT m_bDryRun) THEN
                        m_abCupOk[i] := m_Tool.astStat[m_iTool].abCupFbk[m_stJob.astItems[i].uiCup];
                    ELSE
                        m_abCupOk[i] := TRUE;   (* Verification disabled *)
                    END_IF
                    IF m_abCupOk[i] THEN
                        m_stJob.astItems[i].bPicked := TRUE;
                    END_IF
                END_FOR
            END_IF
            (* Find the next failed cup that still has a retry budget *)
            bOk := FALSE;               (* Reuse as "re-grip started" flag *)
            FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
                IF m_stJob.astItems[i].bPick
                   AND (NOT m_abCupOk[i]) AND (NOT m_stJob.astItems[i].bNg) THEN
                    IF m_auiCupRetry[i] < stCfg.uiRetries THEN
                        m_auiCupRetry[i] := m_auiCupRetry[i] + UINT#1;
                        m_iItem := i;
                        m_bRegrip := TRUE;
                        THIS.CompPickTargets();     (* Individual descent *)
                        m_eSt := ET_SP_RobState#TrackPick;
                        bOk := TRUE;
                        EXIT;
                    ELSE
                        m_stJob.astItems[i].bNg := TRUE;
                        m_bPickNg := TRUE;
                    END_IF
                END_IF
            END_FOR
            IF NOT bOk THEN
                m_eSt := ET_SP_RobState#Depart;     (* Cluster closed *)
            END_IF

        ET_SP_RobState#Depart:
            IF m_bEnter THEN
                (* FW-1: after a native pick the lift-off stays tracked (the
                   product is in the gripper, the session follows the belt
                   until the next static move aborts it); in fallback mode
                   the adapter routes this TrackAbs to the world target. *)
                THIS.MvToBelt(m_stDep, m_stDepBelt,
                              stCfg.rVelApp, stCfg.ePrecApp);
            ELSIF m_Mot.bDone THEN
                m_eSt := ET_SP_RobState#PlanPick;
            END_IF

        (* ------------------------------ PLACE --------------------------- *)
        ET_SP_RobState#PlanPlace:
            IF NOT m_bJobVld THEN
                m_eSt := ET_SP_RobState#WaitJob;
            ELSIF THIS.SyncPlaceTry() THEN
                (* R-07: all pending targets fit the head: one descent *)
                m_bPicking := FALSE;
                m_eSt := ET_SP_RobState#MovePlace;
            ELSIF THIS.AdvancePlaceItem() THEN
                THIS.CompPlaceTargets();
                m_bPicking := FALSE;
                m_eSt := ET_SP_RobState#MovePlace;
            ELSIF stCfg.bDeferVerify AND (NOT m_bDryRun) THEN
                m_eSt := ET_SP_RobState#Verify;
            ELSE
                THIS.CloseJob();
            END_IF

        ET_SP_RobState#MovePlace:
            IF m_bEnter THEN
                stJI := m_stJob.astItems[m_iItem];
                m_iTool := UINT_TO_SINT(stJI.uiTool);
                THIS.MvTo(m_stApp, ET_SP_MvKind#LinearAbs,
                          stCfg.rVelApp, stCfg.ePrecApp);
            ELSIF m_Mot.bDone THEN
                m_eSt := ET_SP_RobState#Place;
            END_IF

        ET_SP_RobState#Place:
            IF m_bEnter THEN
                IF m_bTrkPl THEN
                    (* FW-1 v1.4: native tracked place - the session keeps
                       the slot glued to the tray while the belt advances
                       (PCS target = slot-relative offset). The adapter
                       routes to the world cut-off target whenever the
                       tracking request is not accepted. *)
                    THIS.MvToBelt(m_stPt, m_stPtBelt,
                                  stCfg.rVelPlace, stCfg.ePrecPlace);
                ELSE
                    THIS.MvTo(m_stPt, ET_SP_MvKind#LinearAbs,
                              stCfg.rVelPlace, stCfg.ePrecPlace);
                END_IF
            ELSIF m_Mot.bDone THEN
                m_uiToolTo := UDINT#0;
                m_eSt := ET_SP_RobState#Release;
            END_IF

        ET_SP_RobState#Release:
            IF m_bEnter THEN
                bOk := m_Tool.PlaceStart(m_iTool) = ET_SP_RetCode#Done;
                IF NOT bOk THEN
                    THIS.EnterFault(UINT#3);
                END_IF
            ELSE
                m_uiToolTo := m_uiToolTo + uiDtMs;
                IF m_Tool.bDone THEN
                    IF m_bSyncPlaceRun THEN
                        (* R-07: synchronized release finished - evaluate
                           the whole head cup by cup, then re-place the
                           failed items individually (one-shot policy). *)
                        m_bSyncPlaceRun := FALSE;
                        m_bSyncPlaceDone := TRUE;
                        FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
                            stJI := m_stJob.astItems[i];
                            IF stJI.bPlace AND (NOT stJI.bPlaced) AND (NOT stJI.bNg) THEN
                                IF m_bDryRun OR (NOT THIS.CupHolding(UINT_TO_SINT(stJI.uiCup))) THEN
                                    m_stJob.astItems[i].bPlaced := TRUE;
                                END_IF
                                (* Still held: stays pending for the scan below *)
                            END_IF
                        END_FOR
                        (* First failed item with retry budget: individual re-place *)
                        i := THIS.FirstFailedPlace();
                        IF i > 0 THEN
                            m_auiCupRetry[i] := m_auiCupRetry[i] + UINT#1;
                            m_iItem := i;
                            THIS.CompPlaceTargets();
                            m_eSt := ET_SP_RobState#Place;
                        ELSE
                            m_eSt := ET_SP_RobState#Retreat;
                        END_IF
                    ELSE
                        stJI := m_stJob.astItems[m_iItem];
                        IF stCfg.bVerifyPlace AND (NOT m_bDryRun)
                           AND THIS.CupHolding(UINT_TO_SINT(stJI.uiCup)) THEN
                            (* Part still held: retry the place *)
                            m_uiRetry := m_uiRetry + 1;
                            IF m_uiRetry <= stCfg.uiRetries THEN
                                m_eSt := ET_SP_RobState#Place;
                            ELSE
                                m_stJob.astItems[m_iItem].bNg := TRUE;
                                m_bPlaceNg := TRUE;
                                m_uiRetry := 0;
                                m_eSt := ET_SP_RobState#Retreat;
                            END_IF
                        ELSE
                            m_stJob.astItems[m_iItem].bPlaced := TRUE;
                            m_uiRetry := 0;
                            m_eSt := ET_SP_RobState#Retreat;
                        END_IF
                    END_IF
                ELSIF m_uiToolTo > (TIME_TO_UDINT(stCfg.astTools[m_iTool].tRelease) + UDINT#2000) THEN
                    THIS.EnterFault(UINT#3);    (* Release watchdog *)
                END_IF
            END_IF

        ET_SP_RobState#Retreat:
            IF m_bEnter THEN
                IF m_bTrkPl THEN
                    (* FW-1 v1.4: after a native tracked place the lift-off
                       stays tracked, mirroring the pick-side Depart *)
                    THIS.MvToBelt(m_stDep, m_stDepBelt,
                                  stCfg.rVelApp, stCfg.ePrecApp);
                ELSE
                    THIS.MvTo(m_stDep, ET_SP_MvKind#LinearAbs,
                              stCfg.rVelApp, stCfg.ePrecApp);
                END_IF
            ELSIF m_Mot.bDone THEN
                m_eSt := ET_SP_RobState#PlanPlace;
            END_IF

        (* ---------------------------- VERIFY ---------------------------- *)
        ET_SP_RobState#Verify:
            (* Deferred verification: holding state re-checked after the
               place half; NG items are reported to the System. *)
            THIS.CloseJob();

        (* ------------------------- SUPERVISORY -------------------------- *)
        ET_SP_RobState#Paused:
            (* Frozen; resume handled in the body *)

        ET_SP_RobState#Fault:
            IF m_bCmdReset THEN
                THIS.ClearFault();
            END_IF

        ELSE
            m_eSt := ET_SP_RobState#WaitJob;
    END_CASE
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FirstFailedPlace (parent SP_Robot) - internal (R-07)
   First job item whose place failed after the synchronized release and
   still has a per-cup retry budget (0 = none). Items without budget are
   declared NG while scanning.
   ----------------------------------------------------------------------- *)
METHOD FirstFailedPlace : SINT
VAR
    (* Job item scan index (place side) *)
    i : SINT;
END_VAR
    FirstFailedPlace := 0;
    FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
        IF m_stJob.astItems[i].bPlace
           AND (NOT m_stJob.astItems[i].bPlaced)
           AND (NOT m_stJob.astItems[i].bNg) THEN
            IF m_auiCupRetry[i] < stCfg.uiRetries THEN
                FirstFailedPlace := i;
                RETURN;
            ELSE
                m_stJob.astItems[i].bNg := TRUE;
                m_bPlaceNg := TRUE;
            END_IF
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Publish (parent SP_Robot) - internal
   Status snapshot for HMI and load balancer.
   ----------------------------------------------------------------------- *)
METHOD Publish : BOOL
VAR
    (* Job item scan index (place) *)
    i : SINT;
    (* Tool mask rebuilt from per-tool busy states *)
    uiMask : UINT;
    (* TRUE while the robot holds a zone (R-05) *)
    bHold : BOOL;
END_VAR
    Publish := TRUE;                (* Status snapshot published *)
    stOut.eState := m_eSt;
    stOut.bOnline := m_Mot.bEnabled AND (NOT m_bFault);
    stOut.bReady := stOut.bOnline AND (m_eSt = ET_SP_RobState#WaitJob);
    stOut.bBusy := (m_eSt <> ET_SP_RobState#WaitJob)
                   AND (m_eSt <> ET_SP_RobState#Ready)
                   AND (m_eSt <> ET_SP_RobState#Fault);
    stOut.bFault := m_bFault;
    stOut.bPaused := (m_eSt = ET_SP_RobState#Paused);
    stOut.bDryRun := m_bDryRun;
    stOut.uiCurTool := DINT_TO_UINT(SINT_TO_DINT(m_iTool));
    stOut.uiCurFeed := m_stJob.astItems[m_iItem].iFeedPick;
    (* R-05b: place feed of the current job for the collision guard *)
    stOut.uiCurPlaceFeed := UINT#0;
    IF m_bJobVld THEN
        FOR i := 1 TO UINT_TO_SINT(m_stJob.uiCount) DO
            IF (m_stJob.astItems[i].bPlace) AND (m_stJob.astItems[i].iFeedPlace >= 1) THEN
                stOut.uiCurPlaceFeed := DINT_TO_UINT(SINT_TO_DINT(m_stJob.astItems[i].iFeedPlace));
                EXIT;
            END_IF
        END_FOR
    END_IF
    IF m_bJobVld THEN
        stOut.uiJobCnt := m_stJob.uiCount;
    ELSE
        stOut.uiJobCnt := UINT#0;
    END_IF
    stOut.p2Now := m_Mot.p2Now;
    stOut.udiCycles := m_uiCycles;
    stOut.udiPicks := UDINT#0;
    stOut.udiPlaces := UDINT#0;
    FOR i := 1 TO GC_TOOLS DO
        IF stCfg.astTools[i].bUsed THEN
            stOut.udiPicks := stOut.udiPicks + m_Tool.astStat[i].udiPicks;
            stOut.udiPlaces := stOut.udiPlaces + m_Tool.astStat[i].udiPlaces;
        END_IF
    END_FOR
    stOut.rLoadPct := 0.2;
    IF stOut.bBusy THEN
        stOut.rLoadPct := 0.8;
    END_IF
    stOut.uiErrId := m_uiErrId;
    (* v1.4: native tracked place indicator (HMI diagnostics) *)
    stOut.bTrkPlace := m_bTrkPl;

    (* Tool mask for the balancer: bit i-1 = tool i idle *)
    uiMask := UINT#0;
    bHold := FALSE;
    FOR i := 1 TO GC_TOOLS DO
        IF stCfg.astTools[i].bUsed THEN
            IF NOT m_Tool.astStat[i].bHolding THEN
                uiMask := uiMask OR SHL(UINT#1, SINT_TO_INT(i - 1));
            END_IF
        END_IF
        IF m_Tool.astStat[i].bHolding THEN
            bHold := TRUE;
        END_IF
    END_FOR
    stOut.uiToolMask := uiMask;
    stOut.bHolding := bHold;
END_METHOD
