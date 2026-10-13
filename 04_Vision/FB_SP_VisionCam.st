(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FB - SP_VisionCam
   -----------------------------------------------------------------------------
   Purpose   : Per-camera manager (camera driver model supervisor).

   Features (MotoPick 4 parity):
     - Automatic camera control: distance / external / interval / manual
       trigger policies with delayed acquisition support.
     - Multi-feed monitoring with a single camera: per-feed region table;
       trigger distances auto-adjusted for conveyor speed differences
       (speed ratio scaling, clamped 0.5..2.0).
     - Item routing to feeds by region; item ids generated per camera.
     - Driver dispatch: Cognex / Keyence / GenericTCP (Simulated uses the
       InjectItem path from the simulation framework).
     - Camera control ownership (iOwnerRobot) exposed for the automatic
       camera-control transfer during failure resiliency.
   -----------------------------------------------------------------------------
   Harvest flow: driver items -> internal out-queue (feed-tagged) ->
   SP_System drains via GetNextItem and forwards to SP_TrkFeed.FeedItem.
   =============================================================================
*)

FUNCTION_BLOCK SP_VisionCam
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable    : BOOL;            (* Camera enabled by system *)
    rBeltPos   : LREAL;           (* Belt position (reference conveyor) [mm] *)
    rBeltSpeed : LREAL;           (* Signed belt speed [mm/s] *)
    bExtTrig   : BOOL;            (* External trigger input (edge) *)
    rDtSec     : LREAL;           (* Task period [s] *)
    udiTickMs  : UDINT;           (* Monotonic ms tick (GVL_SP_Rtc) *)
    abiFeedFree: ARRAY[1..GC_FEEDS] OF BOOL; (* TRUE = feed queue has space *)
END_VAR
VAR_OUTPUT
    stOut      : ST_SP_VisionStat;(* Published status *)
    out_iFeed  : SINT;            (* Feed tag of the drained item *)
    out_stItem : ST_SP_VisionItem;(* Drained item (with assigned id) *)
END_VAR
VAR
    stCfg    : ST_SP_VisionCfg;   (* Configuration *)
    m_bCfgOk : BOOL;
    m_iCam   : SINT;              (* Camera index 1..GC_CAMS (id space) *)

    (* Brand drivers (explicit instances: no FB arrays) *)
    m_DrvCx  : SP_DrvCognex;
    (* Keyence driver instance (dispatched by cfg.eDrv) *)
    m_DrvKx  : SP_DrvKeyence;
    (* Generic-TCP driver instance (dispatched by cfg.eDrv) *)
    m_DrvGen : SP_DrvGeneric;

    (* Trigger policy engine *)
    m_bTrigReq  : BOOL;           (* Trigger condition met *)
    m_bTrigPulse: BOOL;           (* One-cycle pulse to the driver *)
    m_bExtPrev  : BOOL;
    m_bInit     : BOOL;           (* First cycle: latch reference positions *)
    m_udiLastInt: UDINT;          (* Interval trigger reference tick [ms] *)
    m_fbDelay   : TON;            (* Delayed acquisition timer *)
    m_bDelayRun : BOOL;
    m_bDelayDone: BOOL;           (* TON done flag *)

    (* Harvest out-queue *)
    m_astQ   : ARRAY[1..GC_VIS_MAX2] OF ST_SP_VisionItem;
    (* Destination feed tag per queued item *)
    m_aiQFeed: ARRAY[1..GC_VIS_MAX2] OF SINT;
    (* Items waiting in the harvest out-queue *)
    m_iQCnt  : SINT := 0;
    (* Drain index for GetNextItem *)
    m_iQRd   : SINT := 0;
    (* One-cycle flag: driver signalled a completed image *)
    m_bHarvest  : BOOL;
    m_udiIdGen  : UDINT := 0;     (* Item id generator *)
    m_udiDrop   : UDINT := 0;     (* Dropped items (no region / queue full) *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
m_bTrigPulse := FALSE;

IF NOT (m_bCfgOk AND bEnable) THEN
    stOut.eState := ET_SP_VisionState#Offline;
    THIS.ResetPolicy();
    RETURN;
END_IF

(* 1) Trigger policy engine ----------------------------------------------- *)
THIS.PolicyEngine();

(* 2) Driver dispatch ----------------------------------------------------- *)
CASE stCfg.eDrv OF
    ET_SP_VisionDrv#Cognex:
        m_DrvCx(bEnable := TRUE, bTrig := m_bTrigPulse, udiTickMs := udiTickMs, rBeltPos := rBeltPos,
                eState => stOut.eState, bDone => m_bHarvest, bErr => , uiErr => ,
                bItemsAvail => , out_stItem => );
    ET_SP_VisionDrv#Keyence:
        m_DrvKx(bEnable := TRUE, bTrig := m_bTrigPulse, udiTickMs := udiTickMs, rBeltPos := rBeltPos,
                eState => stOut.eState, bDone => m_bHarvest, bErr => , uiErr => ,
                bItemsAvail => , out_stItem => );
    ET_SP_VisionDrv#GenericTCP:
        m_DrvGen(bEnable := TRUE, bTrig := m_bTrigPulse, udiTickMs := udiTickMs, rBeltPos := rBeltPos,
                 eState => stOut.eState, bDone => m_bHarvest, bErr => , uiErr => ,
                 bItemsAvail => , out_stItem => );
    ELSE
        (* Simulated: items enter through InjectItem; state is published idle *)
        stOut.eState := ET_SP_VisionState#Online;
        m_bHarvest := FALSE;
END_CASE

(* 3) Harvest driver items into the out-queue ----------------------------- *)
IF m_bHarvest THEN
    CASE stCfg.eDrv OF
        ET_SP_VisionDrv#Cognex:    THIS.HarvestFromDrv(TRUE);
        ET_SP_VisionDrv#Keyence:   THIS.HarvestFromDrv(TRUE);
        ET_SP_VisionDrv#GenericTCP:THIS.HarvestFromDrv(TRUE);
        ELSE m_bHarvest := FALSE;
    END_CASE
END_IF

(* 4) Publish runtime stats ----------------------------------------------- *)
stOut.bConn := stOut.eState <> ET_SP_VisionState#Offline;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: ResetPolicy (parent SP_VisionCam)
   Reset the trigger policy engine (called when camera is disabled).
   ----------------------------------------------------------------------- *)
METHOD ResetPolicy : BOOL
    m_bTrigReq := FALSE;
    m_bDelayRun := FALSE;
    m_fbDelay(IN := FALSE, PT := T#0S, Q => , ET => );
    m_bHarvest := FALSE;
    ResetPolicy := TRUE;            (* Policy engine reset executed *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: PolicyEngine (parent SP_VisionCam)
   Evaluate the configured trigger policy and arm the delayed trigger.
   Distance mode scales the per-feed trigger distance with the speed ratio
   (auto-adjustment for conveyor speed differences, MotoPick 4 parity).
   ----------------------------------------------------------------------- *)
METHOD PolicyEngine : BOOL
VAR
    (* Region table loop index *)
    i      : SINT;
    (* Speed-scaled effective trigger distance [mm] *)
    rEff   : LREAL;
    (* Belt travel since the last trigger [mm] *)
    rTrav  : LREAL;
    bAnyF  : BOOL;      (* At least one mapped feed has queue space *)
    bMapOk : BOOL;      (* At least one feed mapped *)
END_VAR
    PolicyEngine := TRUE;           (* Policy evaluation executed *)
    IF NOT m_bInit THEN
        (* Latch references at start to avoid spurious triggers *)
        FOR i := 1 TO GC_FEEDS DO
            stCfg.astMap[i].rLastTrig := rBeltPos;
        END_FOR
        m_udiLastInt := udiTickMs;
        m_bInit := TRUE;
    END_IF

    (* 1) Pending request with delayed acquisition: service the timer *)
    IF m_bTrigReq AND (stCfg.tDelay > T#0S) THEN
        m_fbDelay(IN := TRUE, PT := stCfg.tDelay, Q => m_bDelayDone, ET => );
        IF m_bDelayDone THEN
            THIS.Fire();
        END_IF
        RETURN;
    END_IF

    (* 2) Pending request without delay: fire immediately *)
    IF m_bTrigReq THEN
        THIS.Fire();
        RETURN;
    END_IF

    (* 3) Evaluate the configured policy *)
    CASE stCfg.eTrig OF
        ET_SP_TrigMode#Distance:
            bAnyF := FALSE; bMapOk := FALSE;
            FOR i := 1 TO GC_FEEDS DO
                IF stCfg.astMap[i].iFeed > 0 THEN
                    bMapOk := TRUE;
                    IF abiFeedFree[stCfg.astMap[i].iFeed] THEN
                        bAnyF := TRUE;
                        (* Auto-scaled trigger distance [mm] *)
                        rEff := stCfg.astMap[i].rTrigDist *
                                FUN_SP_Clamp(ABS(rBeltSpeed) /
                                FUN_SP_Clamp(stCfg.astMap[i].rRefSpeed, 1.0, GC_REAL_MAX), 0.5, 2.0);
                        rTrav := ABS(rBeltPos - stCfg.astMap[i].rLastTrig);
                        IF rTrav >= rEff THEN
                            m_bTrigReq := TRUE;
                        END_IF
                    END_IF
                END_IF
            END_FOR
            IF bMapOk AND (NOT bAnyF) THEN
                RETURN;         (* All mapped queues full: defer trigger *)
            END_IF

        ET_SP_TrigMode#External:
            IF bExtTrig AND NOT m_bExtPrev THEN
                m_bTrigReq := TRUE;
            END_IF
            m_bExtPrev := bExtTrig;

        ET_SP_TrigMode#Interval:
            IF (udiTickMs - m_udiLastInt) >= TIME_TO_UDINT(stCfg.tInterval) THEN
                m_bTrigReq := TRUE;
            END_IF

        ELSE
            (* Manual: trigger only through TriggerNow() *)
    END_CASE

    (* 4) Fire now when no delay is configured *)
    IF m_bTrigReq AND (stCfg.tDelay = T#0S) THEN
        THIS.Fire();
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Fire (parent SP_VisionCam) - internal
   Issue the one-cycle trigger pulse, stamp reference positions and
   restart the interval window.
   ----------------------------------------------------------------------- *)
METHOD Fire : BOOL
VAR
    (* Region table loop index *)
    i : SINT;
END_VAR
    Fire := TRUE;                   (* Trigger pulse issued *)
    m_bTrigPulse := TRUE;
    m_bTrigReq := FALSE;
    m_bDelayRun := FALSE;
    m_bDelayDone := FALSE;
    m_fbDelay(IN := FALSE, PT := T#0S, Q => , ET => );
    FOR i := 1 TO GC_FEEDS DO
        stCfg.astMap[i].rLastTrig := rBeltPos;  (* Stamp all regions *)
    END_FOR
    stOut.rLastTrigPos := rBeltPos;
    stOut.udiTriggers := stOut.udiTriggers + 1;
    m_udiLastInt := udiTickMs;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: HarvestFromDrv (parent SP_VisionCam)
   Pull parsed items from the active driver, assign ids, resolve the
   destination feed by region and enqueue. Called by the body.
   ----------------------------------------------------------------------- *)
METHOD HarvestFromDrv : SINT
VAR_INPUT
    bFromEng : BOOL;    (* Reserved: engine based harvest flag *)
END_VAR
VAR
    (* Item pulled from the active driver *)
    stVi : ST_SP_VisionItem;
    (* Region-resolved destination feed (0 = none) *)
    iFeed: SINT;
    (* Region table loop index *)
    i    : SINT;
    (* Items enqueued by this call *)
    iGot : SINT;
END_VAR
    iGot := 0;
    WHILE m_iQCnt < GC_VIS_MAX2 DO
        (* Pull from the active driver instance *)
        IF stCfg.eDrv = ET_SP_VisionDrv#Cognex THEN
            IF NOT m_DrvCx.GetItem() THEN EXIT; END_IF
            stVi := m_DrvCx.out_stItem;
        ELSIF stCfg.eDrv = ET_SP_VisionDrv#Keyence THEN
            IF NOT m_DrvKx.GetItem() THEN EXIT; END_IF
            stVi := m_DrvKx.out_stItem;
        ELSE
            IF NOT m_DrvGen.GetItem() THEN EXIT; END_IF
            stVi := m_DrvGen.out_stItem;
        END_IF

        (* Resolve feed by region table *)
        iFeed := 0;
        FOR i := 1 TO GC_FEEDS DO
            IF (stCfg.astMap[i].iFeed > 0)
               AND (stVi.p2.rY >= stCfg.astMap[i].rYmin)
               AND (stVi.p2.rY <= stCfg.astMap[i].rYmax) THEN
                iFeed := stCfg.astMap[i].iFeed;
                EXIT;
            END_IF
        END_FOR

        IF iFeed = 0 THEN
            m_udiDrop := m_udiDrop + 1;   (* Outside all regions *)
        ELSE
            m_iQCnt := m_iQCnt + 1;
            m_udiIdGen := m_udiIdGen + 1;
            stVi.udiId := SINT_TO_UDINT(m_iCam) * UDINT#1000000 + m_udiIdGen;
            m_astQ[m_iQCnt] := stVi;
            m_aiQFeed[m_iQCnt] := iFeed;
            stOut.udiItems := stOut.udiItems + 1;
            iGot := iGot + 1;
        END_IF
    END_WHILE
    m_bHarvest := FALSE;
    HarvestFromDrv := iGot;         (* Items harvested this call *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetNextItem (parent SP_VisionCam)
   Drain one item from the out-queue into out_stItem with its feed tag in
   out_iFeed. TRUE while items are available.
   ----------------------------------------------------------------------- *)
METHOD GetNextItem : BOOL
    GetNextItem := FALSE;
    IF m_iQRd < m_iQCnt THEN
        m_iQRd := m_iQRd + 1;
        out_iFeed  := m_aiQFeed[m_iQRd];
        out_stItem := m_astQ[m_iQRd];
        GetNextItem := TRUE;
    ELSE
        m_iQCnt := 0;
        m_iQRd  := 0;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: InjectItem (parent SP_VisionCam)
   Inject an item directly (simulation framework / test harness).
   The caller supplies the feed tag. Returns Done or ErrFull.
   ----------------------------------------------------------------------- *)
METHOD InjectItem : ET_SP_RetCode
VAR_INPUT
    (* Item pushed by the simulation *)
    stVi   : ST_SP_VisionItem;
    (* Destination feed tag supplied by the caller *)
    iFeed  : SINT;
END_VAR
    InjectItem := ET_SP_RetCode#Done;
    IF m_iQCnt >= GC_VIS_MAX2 THEN
        InjectItem := ET_SP_RetCode#ErrFull;
        RETURN;
    END_IF
    m_iQCnt := m_iQCnt + 1;
    m_udiIdGen := m_udiIdGen + 1;
    m_astQ[m_iQCnt] := stVi;
    m_astQ[m_iQCnt].udiId := SINT_TO_UDINT(m_iCam) * UDINT#1000000 + m_udiIdGen;
    m_astQ[m_iQCnt].bValid := TRUE;
    m_aiQFeed[m_iQCnt] := iFeed;
    stOut.udiItems := stOut.udiItems + 1;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_VisionCam)
   Validate and store configuration; bind camera index for the id space.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Configuration to validate and store *)
    stIn  : ST_SP_VisionCfg;
    iCam  : SINT;       (* 1..GC_CAMS *)
END_VAR
    Configure := ET_SP_RetCode#Done;
    IF (iCam < 1) OR (iCam > GC_CAMS) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF stIn.eDrv <> ET_SP_VisionDrv#Simulated THEN
        (* TCP drivers need addressing *)
        IF (stIn.uiPort = 0) OR (LEN(stIn.sIp) = 0) THEN
            Configure := ET_SP_RetCode#ErrParam;
            RETURN;
        END_IF
    END_IF
    stCfg  := stIn;
    m_iCam := iCam;
    m_bCfgOk := TRUE;
END_METHOD
