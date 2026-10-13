(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : PROGRAM - PRG_SP_TaskFast (motion task, ~2 ms)
   -----------------------------------------------------------------------------
   Purpose   : Motion-critical program of the 3-task build (v1.6). Owns every
               FB instance that interacts with encoders, robot groups,
               tracking sessions and cameras, and executes the fast loop:

     time -> config apply (fast layer) -> sim belts -> conveyors ->
     feeds(housekeeping/mirrors) -> collision guard -> robots(bodies) ->
     mirrors(HMI fresh) -> cameras(+drain to feeds) -> sim cameras ->
     pattern engines(+targets to feeds) -> dispatcher side effects

   Why this loop is isolated (performance model, see 00_TaskConfig_IT-EN.md):
     - MC_TrackConveyorBelt sessions and conveyor encoders need the
       smallest, least jittery dt: no file I/O, no string building, no
       HMI service copies ever run in this task.
     - The dispatcher REQUESTS produced by PRG_SP_TaskMain are latched
       (SP_Dispatch v1.6 protocol): the side effects (feed.Reserve /
       ReserveCluster, rob.OfferJob, feed.CompletePick / Release,
       patt.NotifyPlaced) run here, exactly once per request.
     - Production statistics become events in a ring (GVL_SP_Sync) applied
       by the application task - no cross-task FB calls.
     - HMI "fresh data" mirrors (robots, feeds, cameras, system, collision)
       are published here with single-writer semantics.

   All FB calls with VAR_IN_OUT (conveyors, robots) happen HERE in the
   program body - the single allowed place outside the adapters.
   Instance count = system scale (4 robots, 8 feeds, 2 cameras).

   Task assignment (iCube Engineer, see 00_TaskConfig_IT-EN.md):
     SP_Fast_2ms  cyclic 2 ms, highest priority, watchdog 10 ms.
   Task-agnostic: assigning this program to the same task as the other two
   keeps identical semantics (set GVL_SP_Prod.g_uiDtMs to that period).
   =============================================================================
*)

PROGRAM PRG_SP_TaskFast
VAR
    (* --------------------------- Instances ------------------------------ *)
    conv1, conv2, conv3, conv4, conv5, conv6, conv7, conv8 : SP_Conveyor;
    (* Virtual conveyor encoders (one per feed, simulation only) *)
    sim1,  sim2,  sim3,  sim4,  sim5,  sim6,  sim7,  sim8  : SP_SimConveyor;
    (* Tracking feed managers (camera frame pipeline + queue) *)
    feed1, feed2, feed3, feed4, feed5, feed6, feed7, feed8 : SP_TrkFeed;
    (* Camera managers (driver dispatch + harvest out-queue) *)
    cam1, cam2                                            : SP_VisionCam;
    (* Virtual cameras (item spawners, simulation only) *)
    simCam1, simCam2                                      : SP_SimCamera;
    (* Robot FSM instances (one per physical robot) *)
    rob1, rob2, rob3, rob4                                : SP_Robot;
    (* Pattern generators (one per outfeed) *)
    patt1, patt2                                          : SP_PatternGen;
    (* Zone interlock guard (R-05, default disabled) *)
    zg                                                    : SP_ZoneGuard;
    (* Advanced collision guard (R-05b: zones + speed limits + separation) *)
    col                                                   : SP_Collision;

    (* --------------------------- Locals ---------------------------------- *)
    m_bInit   : BOOL := TRUE;           (* First-scan boot latch *)
    aFeedFree : ARRAY[1..GC_FEEDS] OF BOOL;   (* Queue space flags (cameras) *)
    (* Nearest-item distance per feed (slow/stop arbitration) *)
    rNear     : ARRAY[1..GC_FEEDS] OF LREAL;
    aZoneReq  : ARRAY[1..GC_ROBOTS] OF BOOL;    (* R-05: zone guard requests *)
    aiZoneFeed: ARRAY[1..GC_ROBOTS] OF SINT;    (* R-05: feed per robot *)
    (* R-05b: effective grant / velocity scale muxed to the robots *)
    abZoneOk  : ARRAY[1..GC_ROBOTS] OF BOOL;
    arVs      : ARRAY[1..GC_ROBOTS] OF LREAL;   (* Velocity scale (mux output) *)
    (* R-05b: place feed zone per robot (collision request building) *)
    aiZonePl  : ARRAY[1..GC_ROBOTS] OF SINT;
    (* R-07: cluster request scratch (geometry fill from the tool cfg) *)
    stCl      : ST_SP_ClReq;
    eRc, eRc2 : ET_SP_RetCode;          (* Enumerated call results *)
    (* Boolean call result scratch *)
    bRc       : BOOL;
    (* General-purpose loop indices *)
    iD, kD    : DINT;
    (* Reservation request handed to the feed queue *)
    stReq     : ST_SP_ResReq;
    (* Item drained from a camera manager *)
    stVi      : ST_SP_VisionItem;
    (* Operation success flag scratch *)
    bOk       : BOOL;
    (* TRUE while a reservation handshake is in flight *)
    bResPend  : BOOL;
    (* TRUE while a release handshake is in flight *)
    bReleasePend : BOOL;
    stResJob  : ST_SP_Job;              (* Result under processing *)
    stRelJob  : ST_SP_Job;              (* Job to release (refused/cancel) *)
    stJI      : ST_SP_JobItem;          (* Job item scratch (results/release) *)
    (* Statistics event under construction (ring push) *)
    stEv      : ST_SP_StatEv;
    udiIdx    : UDINT;                  (* Ring slot index for the push *)
    (* Grip feedback scratch (simulation loop-back) *)
    bFbk      : BOOL;
END_VAR

(* =========================================================================
   1) TIME SOURCE (single point, fast task) - v1.8.0
      Monotonic millisecond tick: advanced by the configured task period in
      BOTH modes (simulation and hardware). This is the only legal time base
      for durations (socket/camera timeouts, trigger intervals): it never
      jumps, so wall-clock adjustments (NTP / DST / manual RTC set) cannot
      distort a supervision window. Wrap-safe: consumers use unsigned
      subtraction (elapsed := g_udiTickMs - udiMark), correct for any
      elapsed far below the 49.7 day UDINT wrap.
      The WALL CLOCK (log/alarm timestamps, HMI display) is a separate
      service: Y_YA_RealTimeClock in PRG_SP_TaskSvc section 1 (GVL_SP_Rtc).
   ========================================================================= *)
g_udiTickMs := g_udiTickMs + g_uiDtMs;

(* =========================================================================
   2) CONFIGURATION APPLICATION (fast layer, one-shot + re-apply request)
      Triggered at boot and whenever PRG_SP_TaskMain latches bCfgPend
      (HMI apply pulse / recipe import end). Configure calls must run in
      the same task that cycles the FB bodies.
   ========================================================================= *)
IF m_bInit OR GVL_SP_Sync.bCfgPend THEN
    m_bInit := FALSE;
    GVL_SP_Sync.bCfgPend := FALSE;

    (* R-06: commissioning defaults for zeroed robot configurations
       (first boot). Already commissioned records pass through unchanged. *)
    g_astRobCfg[1] := FUN_SP_RobCfgDefault(g_astRobCfg[1], 1);
    g_astRobCfg[2] := FUN_SP_RobCfgDefault(g_astRobCfg[2], 2);
    g_astRobCfg[3] := FUN_SP_RobCfgDefault(g_astRobCfg[3], 3);
    g_astRobCfg[4] := FUN_SP_RobCfgDefault(g_astRobCfg[4], 4);

    (* HW-4: camera model presets (selector in GVL_SP_Hmi.g_aiCamModel,
       -1 = Cognex, 1 = Keyence, 2 = GenericTCP, 3 = Simulated, 0 = keep).
       Applied BEFORE Configure so the driver protocol presets compose. *)
    IF GVL_SP_Hmi.g_aiCamModel[1] <> 0 THEN
        g_astCamCfg[1] := FUN_SP_CamPreset(g_astCamCfg[1], GVL_SP_Hmi.g_aiCamModel[1]);
    END_IF
    IF GVL_SP_Hmi.g_aiCamModel[2] <> 0 THEN
        g_astCamCfg[2] := FUN_SP_CamPreset(g_astCamCfg[2], GVL_SP_Hmi.g_aiCamModel[2]);
    END_IF

    eRc := conv1.Configure(g_astConvCfg[1]);  eRc := conv2.Configure(g_astConvCfg[2]);
    eRc := conv3.Configure(g_astConvCfg[3]);  eRc := conv4.Configure(g_astConvCfg[4]);
    eRc := conv5.Configure(g_astConvCfg[5]);  eRc := conv6.Configure(g_astConvCfg[6]);
    eRc := conv7.Configure(g_astConvCfg[7]);  eRc := conv8.Configure(g_astConvCfg[8]);

    eRc := feed1.Configure(g_astFeedCfg[1]);  eRc := feed2.Configure(g_astFeedCfg[2]);
    eRc := feed3.Configure(g_astFeedCfg[3]);  eRc := feed4.Configure(g_astFeedCfg[4]);
    eRc := feed5.Configure(g_astFeedCfg[5]);  eRc := feed6.Configure(g_astFeedCfg[6]);
    eRc := feed7.Configure(g_astFeedCfg[7]);  eRc := feed8.Configure(g_astFeedCfg[8]);

    eRc := cam1.Configure(g_astCamCfg[1], 1);
    eRc := cam2.Configure(g_astCamCfg[2], 2);

    eRc := rob1.Configure(g_astRobCfg[1], 1); eRc := rob2.Configure(g_astRobCfg[2], 2);
    eRc := rob3.Configure(g_astRobCfg[3], 3); eRc := rob4.Configure(g_astRobCfg[4], 4);

    (* FW-1 native conveyor tracking: derive the per-feed belt frames
       (MC_TrackConveyorBelt session geometry) from the feed configs.
       The run-time switch is GVL_SP_Fw.g_eTrkMode (0 = fallback cut-off,
       1 = native tracked picks); feeds with bUsed = FALSE always run the
       fallback path. Belt axes are bound below in section 6 (ioaBelt). *)
    eRc := rob1.SetBeltFrames(g_astFeedCfg);
    eRc := rob2.SetBeltFrames(g_astFeedCfg);
    eRc := rob3.SetBeltFrames(g_astFeedCfg);
    eRc := rob4.SetBeltFrames(g_astFeedCfg);

    (* Pattern generators bind the frame of their outfeed (feed 7 / 8) *)
    eRc := patt1.Configure(g_astFeedCfg[7].stWorld, g_astFeedCfg[7].rZBelt, g_astFeedCfg[7].iDir);
    eRc := patt2.Configure(g_astFeedCfg[8].stWorld, g_astFeedCfg[8].rZBelt, g_astFeedCfg[8].iDir);

    (* R-05: zone guard commissioning. Default map: all feeds unguarded
       (zone 0). Example (configuration 8 of PRG_SP_ConfigInit): feeds
       1..3 = zone 1 (robots 1+2), feeds 4..6 = zone 2 (robots 3+4). *)
    eRc := zg.Configure(g_aiFeedZone);

    (* R-05b: advanced collision guard - zone map + safe default config
       (fill-if-empty; tune distances/priorities in the HMI editor). *)
    eRc := col.Configure(g_aiFeedZone);
    IF g_stColCfg.rSlowDist <= 0.0 THEN g_stColCfg.rSlowDist := 300.0; END_IF
    IF g_stColCfg.rStopDist <= 0.0 THEN g_stColCfg.rStopDist := 150.0; END_IF
    FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
        IF (g_stColCfg.aiPriority[iD] < 1) OR (g_stColCfg.aiPriority[iD] > GC_ROBOTS) THEN
            g_stColCfg.aiPriority[iD] := DINT_TO_SINT(iD);  (* Default ranks *)
        END_IF
    END_FOR
    FOR iD := 1 TO SINT_TO_DINT(GC_ZONES) DO
        IF (g_stColCfg.arZoneLim[iD] <= 0.0) OR (g_stColCfg.arZoneLim[iD] > 1.0) THEN
            g_stColCfg.arZoneLim[iD] := 1.0;    (* Full speed by default *)
        END_IF
    END_FOR
    col.stCfg := g_stColCfg;
END_IF

(* =========================================================================
   3) SIMULATED CONVEYORS (simulation mode only)
      NOTE: the slow/stop factor comes from the conveyor of the previous
      scan (one-cycle latency, irrelevant at task rate).
   ========================================================================= *)
sim1(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[1].rMaxSpeed, rFactor := conv1.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim2(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[2].rMaxSpeed, rFactor := conv2.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim3(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[3].rMaxSpeed, rFactor := conv3.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim4(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[4].rMaxSpeed, rFactor := conv4.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim5(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[5].rMaxSpeed, rFactor := conv5.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim6(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[6].rMaxSpeed, rFactor := conv6.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim7(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[7].rMaxSpeed, rFactor := conv7.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );
sim8(bRun := g_Sys.stOut.bRunning, rSetSpd := g_astConvCfg[8].rMaxSpeed, rFactor := conv8.stOut.rReqFactor, uiDtMs := g_uiDtMs, rPos => , rSpeed => );

(* =========================================================================
   4) CONVEYORS (encoder + drive adapters inside; VAR_IN_OUT bound here)
   ========================================================================= *)
conv1(bEnable := g_Sys.abConvEnable[1], rNearDist := rNear[1], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim1.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[1]);
conv2(bEnable := g_Sys.abConvEnable[2], rNearDist := rNear[2], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim2.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[2]);
conv3(bEnable := g_Sys.abConvEnable[3], rNearDist := rNear[3], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim3.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[3]);
conv4(bEnable := g_Sys.abConvEnable[4], rNearDist := rNear[4], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim4.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[4]);
conv5(bEnable := g_Sys.abConvEnable[5], rNearDist := rNear[5], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim5.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[5]);
conv6(bEnable := g_Sys.abConvEnable[6], rNearDist := rNear[6], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim6.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[6]);
conv7(bEnable := g_Sys.abConvEnable[7], rNearDist := rNear[7], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim7.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[7]);
conv8(bEnable := g_Sys.abConvEnable[8], rNearDist := rNear[8], rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0,
      bSim := g_bSim, rSimPos := sim8.rPos, rSimFrc := 1.0, ioAxis := g_aAxisEnc[8]);

(* Live run vector for the maintenance engine (R-16, service task reads) *)
g_abConvRun[1] := g_Sys.abConvEnable[1]; g_abConvRun[2] := g_Sys.abConvEnable[2];
g_abConvRun[3] := g_Sys.abConvEnable[3]; g_abConvRun[4] := g_Sys.abConvEnable[4];
g_abConvRun[5] := g_Sys.abConvEnable[5]; g_abConvRun[6] := g_Sys.abConvEnable[6];
g_abConvRun[7] := g_Sys.abConvEnable[7]; g_abConvRun[8] := g_Sys.abConvEnable[8];

(* =========================================================================
   5) FEEDS: housekeeping, nearest distance, queue space flags, mirror
   ========================================================================= *)
eRc := feed1.Housekeeping(conv1.stOut.rPos, g_uiDtMs);
bFbk := feed1.NearDist(conv1.stOut.rPos);
IF bFbk THEN rNear[1] := feed1.out_rNear; ELSE rNear[1] := GC_REAL_MAX; END_IF
aFeedFree[1] := (feed1.stOut.uiTracked + feed1.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed2.Housekeeping(conv2.stOut.rPos, g_uiDtMs);
bFbk := feed2.NearDist(conv2.stOut.rPos);
IF bFbk THEN rNear[2] := feed2.out_rNear; ELSE rNear[2] := GC_REAL_MAX; END_IF
aFeedFree[2] := (feed2.stOut.uiTracked + feed2.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed3.Housekeeping(conv3.stOut.rPos, g_uiDtMs);
bFbk := feed3.NearDist(conv3.stOut.rPos);
IF bFbk THEN rNear[3] := feed3.out_rNear; ELSE rNear[3] := GC_REAL_MAX; END_IF
aFeedFree[3] := (feed3.stOut.uiTracked + feed3.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed4.Housekeeping(conv4.stOut.rPos, g_uiDtMs);
bFbk := feed4.NearDist(conv4.stOut.rPos);
IF bFbk THEN rNear[4] := feed4.out_rNear; ELSE rNear[4] := GC_REAL_MAX; END_IF
aFeedFree[4] := (feed4.stOut.uiTracked + feed4.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed5.Housekeeping(conv5.stOut.rPos, g_uiDtMs);
bFbk := feed5.NearDist(conv5.stOut.rPos);
IF bFbk THEN rNear[5] := feed5.out_rNear; ELSE rNear[5] := GC_REAL_MAX; END_IF
aFeedFree[5] := (feed5.stOut.uiTracked + feed5.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed6.Housekeeping(conv6.stOut.rPos, g_uiDtMs);
bFbk := feed6.NearDist(conv6.stOut.rPos);
IF bFbk THEN rNear[6] := feed6.out_rNear; ELSE rNear[6] := GC_REAL_MAX; END_IF
aFeedFree[6] := (feed6.stOut.uiTracked + feed6.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed7.Housekeeping(conv7.stOut.rPos, g_uiDtMs);
bFbk := feed7.NearDist(conv7.stOut.rPos);
IF bFbk THEN rNear[7] := feed7.out_rNear; ELSE rNear[7] := GC_REAL_MAX; END_IF
aFeedFree[7] := (feed7.stOut.uiTracked + feed7.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

eRc := feed8.Housekeeping(conv8.stOut.rPos, g_uiDtMs);
bFbk := feed8.NearDist(conv8.stOut.rPos);
IF bFbk THEN rNear[8] := feed8.out_rNear; ELSE rNear[8] := GC_REAL_MAX; END_IF
aFeedFree[8] := (feed8.stOut.uiTracked + feed8.stOut.uiReserved) < UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);

g_astFeedIo[1].iFeed := 1;  g_astFeedIo[1].bUsed := g_astFeedCfg[1].bUsed;
g_astFeedIo[1].rEnc := conv1.stOut.rPos;  g_astFeedIo[1].rSpeed := conv1.stOut.rSpeed;
g_astFeedIo[1].stStat := feed1.stOut;
g_astFeedIo[1].rNearOff := rNear[1];
g_astFeedIo[1].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[1].stWorld, 0.0, 0.0);
g_astFeedIo[1].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[1].stWorld, 0.0, 0.0);
g_astFeedIo[1].bIsOutfeed := FALSE;
g_astFeedIo[2].iFeed := 2;  g_astFeedIo[2].bUsed := g_astFeedCfg[2].bUsed;
g_astFeedIo[2].rEnc := conv2.stOut.rPos;  g_astFeedIo[2].rSpeed := conv2.stOut.rSpeed;
g_astFeedIo[2].stStat := feed2.stOut;
g_astFeedIo[2].rNearOff := rNear[2];
g_astFeedIo[2].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[2].stWorld, 0.0, 0.0);
g_astFeedIo[2].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[2].stWorld, 0.0, 0.0);
g_astFeedIo[2].bIsOutfeed := FALSE;
g_astFeedIo[3].iFeed := 3;  g_astFeedIo[3].bUsed := g_astFeedCfg[3].bUsed;
g_astFeedIo[3].rEnc := conv3.stOut.rPos;  g_astFeedIo[3].rSpeed := conv3.stOut.rSpeed;
g_astFeedIo[3].stStat := feed3.stOut;
g_astFeedIo[3].rNearOff := rNear[3];
g_astFeedIo[3].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[3].stWorld, 0.0, 0.0);
g_astFeedIo[3].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[3].stWorld, 0.0, 0.0);
g_astFeedIo[3].bIsOutfeed := FALSE;
g_astFeedIo[4].iFeed := 4;  g_astFeedIo[4].bUsed := g_astFeedCfg[4].bUsed;
g_astFeedIo[4].rEnc := conv4.stOut.rPos;  g_astFeedIo[4].rSpeed := conv4.stOut.rSpeed;
g_astFeedIo[4].stStat := feed4.stOut;
g_astFeedIo[4].rNearOff := rNear[4];
g_astFeedIo[4].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[4].stWorld, 0.0, 0.0);
g_astFeedIo[4].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[4].stWorld, 0.0, 0.0);
g_astFeedIo[4].bIsOutfeed := FALSE;
g_astFeedIo[5].iFeed := 5;  g_astFeedIo[5].bUsed := g_astFeedCfg[5].bUsed;
g_astFeedIo[5].rEnc := conv5.stOut.rPos;  g_astFeedIo[5].rSpeed := conv5.stOut.rSpeed;
g_astFeedIo[5].stStat := feed5.stOut;
g_astFeedIo[5].rNearOff := rNear[5];
g_astFeedIo[5].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[5].stWorld, 0.0, 0.0);
g_astFeedIo[5].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[5].stWorld, 0.0, 0.0);
g_astFeedIo[5].bIsOutfeed := FALSE;
g_astFeedIo[6].iFeed := 6;  g_astFeedIo[6].bUsed := g_astFeedCfg[6].bUsed;
g_astFeedIo[6].rEnc := conv6.stOut.rPos;  g_astFeedIo[6].rSpeed := conv6.stOut.rSpeed;
g_astFeedIo[6].stStat := feed6.stOut;
g_astFeedIo[6].rNearOff := rNear[6];
g_astFeedIo[6].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[6].stWorld, 0.0, 0.0);
g_astFeedIo[6].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[6].stWorld, 0.0, 0.0);
g_astFeedIo[6].bIsOutfeed := FALSE;
g_astFeedIo[7].iFeed := 7;  g_astFeedIo[7].bUsed := g_astFeedCfg[7].bUsed;
g_astFeedIo[7].rEnc := conv7.stOut.rPos;  g_astFeedIo[7].rSpeed := conv7.stOut.rSpeed;
g_astFeedIo[7].stStat := feed7.stOut;
g_astFeedIo[7].rNearOff := rNear[7];
g_astFeedIo[7].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[7].stWorld, 0.0, 0.0);
g_astFeedIo[7].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[7].stWorld, 0.0, 0.0);
g_astFeedIo[7].bIsOutfeed := TRUE;
g_astFeedIo[8].iFeed := 8;  g_astFeedIo[8].bUsed := g_astFeedCfg[8].bUsed;
g_astFeedIo[8].rEnc := conv8.stOut.rPos;  g_astFeedIo[8].rSpeed := conv8.stOut.rSpeed;
g_astFeedIo[8].stStat := feed8.stOut;
g_astFeedIo[8].rNearOff := rNear[8];
g_astFeedIo[8].stPickLineW.rX := FUN_SP_TrfX(g_astFeedCfg[8].stWorld, 0.0, 0.0);
g_astFeedIo[8].stPickLineW.rY := FUN_SP_TrfY(g_astFeedCfg[8].stWorld, 0.0, 0.0);
g_astFeedIo[8].bIsOutfeed := TRUE;

(* Feed on/off vector + outfeed map for the dispatcher (GVL instance) *)
g_Disp.abiFeedOn[1] := g_astFeedCfg[1].bUsed; g_Disp.abiFeedOn[2] := g_astFeedCfg[2].bUsed;
g_Disp.abiFeedOn[3] := g_astFeedCfg[3].bUsed; g_Disp.abiFeedOn[4] := g_astFeedCfg[4].bUsed;
g_Disp.abiFeedOn[5] := g_astFeedCfg[5].bUsed; g_Disp.abiFeedOn[6] := g_astFeedCfg[6].bUsed;
g_Disp.abiFeedOn[7] := FALSE; g_Disp.abiFeedOn[8] := FALSE;  (* outfeeds: no picking *)
g_Disp.aiOutfeed := g_stShareCfg.aiOutfeedMap;

(* =========================================================================
   5b) COLLISION PREVENTION (R-05 base + R-05b advanced)
   The legacy ZoneGuard enforces one-zone-per-robot exclusion. The
   advanced SP_Collision adds multi-zone ordered acquisition, zone speed
   limits and dynamic TCP separation (g_stSysCfg.bColAdv selects it).
   Requests come from the status mirrors of the previous cycle (one-cycle
   latency at task rate, same contract as the simulated conveyors).
   ========================================================================= *)
FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
    aZoneReq[iD] := g_astRobStat[iD].bBusy AND (g_astRobStat[iD].uiCurFeed > 0);
    aiZoneFeed[iD] := UINT_TO_SINT(g_astRobStat[iD].uiCurFeed);
    (* Place feed zone (0 when idle or pick-only job) *)
    aiZonePl[iD] := 0;
    kD := UINT_TO_DINT(g_astRobStat[iD].uiCurPlaceFeed);
    IF (kD >= 1) AND (kD <= SINT_TO_DINT(GC_FEEDS)) THEN
        aiZonePl[iD] := g_aiFeedZone[kD];
    END_IF
END_FOR
zg(bEnable := g_stSysCfg.bZoneGuard AND (NOT g_stSysCfg.bColAdv),
   abRobReq := aZoneReq, aiRobFeed := aiZoneFeed);
col(bEnable := g_stSysCfg.bColAdv,
   bSysRun := g_Sys.stOut.bRunning, uiDtMs := g_uiDtMs);
FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
    (* Requests: pick feed zone + place feed zone (FB normalizes) *)
    IF (aiZoneFeed[iD] >= 1) AND (aiZoneFeed[iD] <= SINT_TO_DINT(GC_FEEDS)) THEN
        col.aiReq[iD][1] := g_aiFeedZone[aiZoneFeed[iD]];
    ELSE
        col.aiReq[iD][1] := GC_ZONE_NONE;
    END_IF
    col.aiReq[iD][2] := aiZonePl[iD];
    col.ap2Pos[iD] := g_astRobStat[iD].p2Now;
    (* Mux the active guard to the robot interface *)
    IF g_stSysCfg.bColAdv THEN
        abZoneOk[iD] := col.astRob[iD].bGrant;
        arVs[iD] := col.astRob[iD].rVelScale;
    ELSIF g_stSysCfg.bZoneGuard THEN
        abZoneOk[iD] := zg.abGrant[iD];
        arVs[iD] := 1.0;
    ELSE
        abZoneOk[iD] := TRUE;
        arVs[iD] := 1.0;
    END_IF
END_FOR

(* =========================================================================
   6) ROBOTS (bodies + commands; VAR_IN_OUT groups bound here)
   ========================================================================= *)
rob1.stCmd.bPause  := g_Sys.abRobPause[1];
rob1.stCmd.bResume := g_Sys.abRobResume[1];
rob1.stCmd.bReset  := g_Sys.abRobReset[1];
rob1.stCmd.bDryRun := g_Sys.abRobDryRun[1];
rob1.stCmd.bHome   := g_hmiCmd.bHomeAll;
rob1(bSysRun := g_Sys.stOut.bRunning, bSim := g_bSim, uiDtMs := g_uiDtMs, ioGrp := g_aGrp[1],
     ioaBelt := g_aAxisEnc,
     bFwReady := GVL_SP_Fw.g_abFwGrpReady[1], bFwRef := GVL_SP_Fw.g_abFwGrpRef[1],
     bZoneOk := abZoneOk[1], rVelScale := arVs[1]);
rob2.stCmd.bPause  := g_Sys.abRobPause[2];
rob2.stCmd.bResume := g_Sys.abRobResume[2];
rob2.stCmd.bReset  := g_Sys.abRobReset[2];
rob2.stCmd.bDryRun := g_Sys.abRobDryRun[2];
rob2.stCmd.bHome   := g_hmiCmd.bHomeAll;
rob2(bSysRun := g_Sys.stOut.bRunning, bSim := g_bSim, uiDtMs := g_uiDtMs, ioGrp := g_aGrp[2],
     ioaBelt := g_aAxisEnc,
     bFwReady := GVL_SP_Fw.g_abFwGrpReady[2], bFwRef := GVL_SP_Fw.g_abFwGrpRef[2],
     bZoneOk := abZoneOk[2], rVelScale := arVs[2]);
rob3.stCmd.bPause  := g_Sys.abRobPause[3];
rob3.stCmd.bResume := g_Sys.abRobResume[3];
rob3.stCmd.bReset  := g_Sys.abRobReset[3];
rob3.stCmd.bDryRun := g_Sys.abRobDryRun[3];
rob3.stCmd.bHome   := g_hmiCmd.bHomeAll;
rob3(bSysRun := g_Sys.stOut.bRunning, bSim := g_bSim, uiDtMs := g_uiDtMs, ioGrp := g_aGrp[3],
     ioaBelt := g_aAxisEnc,
     bFwReady := GVL_SP_Fw.g_abFwGrpReady[3], bFwRef := GVL_SP_Fw.g_abFwGrpRef[3],
     bZoneOk := abZoneOk[3], rVelScale := arVs[3]);
rob4.stCmd.bPause  := g_Sys.abRobPause[4];
rob4.stCmd.bResume := g_Sys.abRobResume[4];
rob4.stCmd.bReset  := g_Sys.abRobReset[4];
rob4.stCmd.bDryRun := g_Sys.abRobDryRun[4];
rob4.stCmd.bHome   := g_hmiCmd.bHomeAll;
rob4(bSysRun := g_Sys.stOut.bRunning, bSim := g_bSim, uiDtMs := g_uiDtMs, ioGrp := g_aGrp[4],
     ioaBelt := g_aAxisEnc,
     bFwReady := GVL_SP_Fw.g_abFwGrpReady[4], bFwRef := GVL_SP_Fw.g_abFwGrpRef[4],
     bZoneOk := abZoneOk[4], rVelScale := arVs[4]);
g_hmiCmd.bHomeAll := FALSE;

(* Simulated tool feedback (simulation mode): the pick output loops back
   to the tool feedback input, so pick verification (bVerifyPick) works
   offline without hardware. On site the real inputs are wired instead
   (see Hardware/HW_IO_Map_IT-EN.md). *)
IF g_bSim THEN
    FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) * SINT_TO_DINT(GC_TOOLS) DO
        GVL_SP_Io.abToolFbkIn[iD] := GVL_SP_Io.abPickOut[iD];
    END_FOR
END_IF

(* Resiliency: group-level loss detection *)
IF g_Sys.stOut.bRunning THEN
    IF (NOT rob1.stOut.bOnline) AND (NOT rob1.stOut.bFault) THEN rob1.MarkFault(); END_IF
    IF (NOT rob2.stOut.bOnline) AND (NOT rob2.stOut.bFault) THEN rob2.MarkFault(); END_IF
    IF (NOT rob3.stOut.bOnline) AND (NOT rob3.stOut.bFault) THEN rob3.MarkFault(); END_IF
    IF (NOT rob4.stOut.bOnline) AND (NOT rob4.stOut.bFault) THEN rob4.MarkFault(); END_IF
END_IF

(* =========================================================================
   7) ROBOT STATUS MIRROR (production GVL) + HMI FRESH MIRRORS
      Single writer: THIS task. HMI mirrors are published every fast scan
      so the slow task never copies live motion data (no tear on control
      data; HMI-grade cosmetic tear remains inherent to the HMI reader).
   ========================================================================= *)
g_astRobStat[1] := rob1.stOut;
g_astRobStat[2] := rob2.stOut;
g_astRobStat[3] := rob3.stOut;
g_astRobStat[4] := rob4.stOut;

GVL_SP_Hmi.g_hmiSysStat := g_Sys.stOut;
GVL_SP_Hmi.g_astHmiRob[1] := g_astRobStat[1];
GVL_SP_Hmi.g_astHmiRob[2] := g_astRobStat[2];
GVL_SP_Hmi.g_astHmiRob[3] := g_astRobStat[3];
GVL_SP_Hmi.g_astHmiRob[4] := g_astRobStat[4];
GVL_SP_Hmi.g_astHmiFeed[1] := g_astFeedIo[1];
GVL_SP_Hmi.g_astHmiFeed[2] := g_astFeedIo[2];
GVL_SP_Hmi.g_astHmiFeed[3] := g_astFeedIo[3];
GVL_SP_Hmi.g_astHmiFeed[4] := g_astFeedIo[4];
GVL_SP_Hmi.g_astHmiFeed[5] := g_astFeedIo[5];
GVL_SP_Hmi.g_astHmiFeed[6] := g_astFeedIo[6];
GVL_SP_Hmi.g_astHmiFeed[7] := g_astFeedIo[7];
GVL_SP_Hmi.g_astHmiFeed[8] := g_astFeedIo[8];
GVL_SP_Hmi.g_astHmiCam[1] := cam1.stOut;
GVL_SP_Hmi.g_astHmiCam[2] := cam2.stOut;
FOR kD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
    GVL_SP_Hmi.g_astHmiCol[kD] := col.astRob[kD];
END_FOR

(* =========================================================================
   8) CAMERAS + RESULT DRAIN INTO THE FEEDS
   ========================================================================= *)
cam1(bEnable := g_Sys.abCamEnable[1], rBeltPos := conv1.stOut.rPos, rBeltSpeed := conv1.stOut.rSpeed,
     bExtTrig := FALSE, rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0, udiTickMs := g_udiTickMs, abiFeedFree := aFeedFree);
cam2(bEnable := g_Sys.abCamEnable[2], rBeltPos := conv2.stOut.rPos, rBeltSpeed := conv2.stOut.rSpeed,
     bExtTrig := FALSE, rDtSec := UDINT_TO_LREAL(g_uiDtMs) / 1000.0, udiTickMs := g_udiTickMs, abiFeedFree := aFeedFree);

WHILE cam1.GetNextItem() DO
    stVi := cam1.out_stItem;
    CASE cam1.out_iFeed OF
        1: eRc := feed1.FeedItem(stVi, 1);
        2: eRc := feed2.FeedItem(stVi, 1);
        3: eRc := feed3.FeedItem(stVi, 1);
        4: eRc := feed4.FeedItem(stVi, 1);
        5: eRc := feed5.FeedItem(stVi, 1);
        6: eRc := feed6.FeedItem(stVi, 1);
        ELSE (* unmanaged feed: dropped *)
    END_CASE
END_WHILE

WHILE cam2.GetNextItem() DO
    stVi := cam2.out_stItem;
    CASE cam2.out_iFeed OF
        1: eRc := feed1.FeedItem(stVi, 2);
        2: eRc := feed2.FeedItem(stVi, 2);
        3: eRc := feed3.FeedItem(stVi, 2);
        4: eRc := feed4.FeedItem(stVi, 2);
        5: eRc := feed5.FeedItem(stVi, 2);
        6: eRc := feed6.FeedItem(stVi, 2);
        ELSE (* unmanaged feed: dropped *)
    END_CASE
END_WHILE

(* =========================================================================
   9) SIMULATED CAMERAS (simulation mode): spawn + inject
   ========================================================================= *)
simCam1(bEnable := g_bSim AND g_Sys.stOut.bRunning, iCam := 1, iFeed := 1,
        rEncNow := conv1.stOut.rPos, uiDtMs := g_uiDtMs);
WHILE simCam1.GetNextItem() DO
    stVi := simCam1.out_stItem;
    CASE stVi.uiTypeId MOD 6 OF
        0: eRc := cam1.InjectItem(stVi, 1);
        1: eRc := cam1.InjectItem(stVi, 2);
        2: eRc := cam1.InjectItem(stVi, 3);
        3: eRc := cam1.InjectItem(stVi, 4);
        4: eRc := cam1.InjectItem(stVi, 5);
        ELSE eRc := cam1.InjectItem(stVi, 6);
    END_CASE
END_WHILE

simCam2(bEnable := g_bSim AND g_Sys.stOut.bRunning, iCam := 2, iFeed := 1,
        rEncNow := conv2.stOut.rPos, uiDtMs := g_uiDtMs);
WHILE simCam2.GetNextItem() DO
    stVi := simCam2.out_stItem;
    eRc := cam2.InjectItem(stVi, 1);
END_WHILE

(* =========================================================================
   10) PATTERN ENGINES (outfeeds 7 and 8)
       Batch start/stop arrive through the GVL_SP_Sync.stPattCmd mailbox
       (latched by the application task); engine cycles and target feed
       stay in THIS task (queue access must be single-task).
   ========================================================================= *)
IF GVL_SP_Sync.stPattCmd[1].bStart THEN
    GVL_SP_Sync.stPattCmd[1].bStart := FALSE;
    eRc := patt1.StartBatch(GVL_SP_Sync.stPattCmd[1].stDef,
                            GVL_SP_Sync.stPattCmd[1].stPatt,
                            GVL_SP_Sync.stPattCmd[1].udiBatchId);
END_IF
IF GVL_SP_Sync.stPattCmd[2].bStart THEN
    GVL_SP_Sync.stPattCmd[2].bStart := FALSE;
    eRc := patt2.StartBatch(GVL_SP_Sync.stPattCmd[2].stDef,
                            GVL_SP_Sync.stPattCmd[2].stPatt,
                            GVL_SP_Sync.stPattCmd[2].udiBatchId);
END_IF
IF GVL_SP_Sync.stPattCmd[1].bAbort THEN
    GVL_SP_Sync.stPattCmd[1].bAbort := FALSE;
    patt1.AbortBatch();
END_IF
IF GVL_SP_Sync.stPattCmd[2].bAbort THEN
    GVL_SP_Sync.stPattCmd[2].bAbort := FALSE;
    patt2.AbortBatch();
END_IF

eRc := patt1.Engine(conv7.stOut.rPos);
eRc := patt2.Engine(conv8.stOut.rPos);
IF GVL_SP_Io.abTraySensor[7] THEN eRc := patt1.OnSensor(conv7.stOut.rPos); END_IF
IF GVL_SP_Io.abTraySensor[8] THEN eRc := patt2.OnSensor(conv8.stOut.rPos); END_IF

WHILE patt1.GetNextTarget() DO
    eRc := feed7.AddTarget(patt1.out_stTarget);
END_WHILE
WHILE patt2.GetNextTarget() DO
    eRc := feed8.AddTarget(patt2.out_stTarget);
END_WHILE

(* Publish the engine status for the application task (batch progress) *)
GVL_SP_Sync.stPattStat[1] := patt1.stStat;
GVL_SP_Sync.stPattStat[2] := patt2.stStat;

(* =========================================================================
   11) DISPATCHER SIDE EFFECTS (latched requests from PRG_SP_TaskMain)
       The application task runs SP_Dispatch.Run() and latches requests;
       THIS task executes them exactly once against the tracking queues
       and the robots, then publishes the responses.
   ========================================================================= *)
bReleasePend := FALSE;

FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO

    (* ----- 11a) Reservation requests -> feed.Reserve / ReserveCluster -- *)
    IF g_Disp.abReqPulse[iD] AND g_Disp.astReq[iD].bReq THEN
        g_Disp.abReqPulse[iD] := FALSE;     (* Consume the latched request *)
        kD := FUN_SP_ClampI(SINT_TO_DINT(g_Disp.astReq[iD].iFeed), 1, GC_FEEDS);
        stReq.iRobotId := iD;
        stReq.rRangeFrom := g_stShareCfg.arRangeFrom[kD][iD];
        stReq.rRangeTo   := g_stShareCfg.arRangeTo[kD][iD];
        stReq.uiTypeId   := g_Disp.astReq[iD].uiTypeId;
        stReq.bTargetOnly:= g_Disp.astReq[iD].bTargetOnly;
        stReq.rMaxWeight := g_Disp.astReq[iD].rMaxWeight;
        IF g_Disp.astReq[iD].bCluster THEN
            (* R-07: cluster reservation - geometry and rules come from the
               robot tool configuration (single source of truth) *)
            stCl := g_Disp.astReq[iD].stCl;
            stCl.iRobotId := iD;
            stCl.rRangeFrom := g_stShareCfg.arRangeFrom[kD][iD];
            stCl.rRangeTo   := g_stShareCfg.arRangeTo[kD][iD];
            stCl.uiTypeId   := UINT#0;
            stCl.rMaxWeight := g_astRobCfg[iD].astTools[1].rMaxWeight;
            stCl.uiCups     := g_astRobCfg[iD].astTools[1].uiCups;
            IF stCl.uiCups > g_astRobCfg[iD].uiMaxGrip THEN
                stCl.uiCups := g_astRobCfg[iD].uiMaxGrip;
            END_IF
            stCl.astCup     := g_astRobCfg[iD].astTools[1].astCups;
            stCl.bSingleType:= g_astRobCfg[iD].astTools[1].bSingleType;
            stCl.rMatchTol  := g_astRobCfg[iD].astTools[1].rMatchTol;
            stCl.rMinGap    := 0.0;     (* Enable from the product data *)
            stCl.rMaxCog    := g_astRobCfg[iD].astTools[1].rCapCog;
            g_Disp.astReq[iD].stCl := stCl;
            CASE kD OF
                1: eRc := feed1.ReserveCluster(stCl, g_astFeedIo[1].rEnc, g_astFeedIo[1].rSpeed);
                    g_Disp.astClRsp[iD] := feed1.out_stCl;
                2: eRc := feed2.ReserveCluster(stCl, g_astFeedIo[2].rEnc, g_astFeedIo[2].rSpeed);
                    g_Disp.astClRsp[iD] := feed2.out_stCl;
                3: eRc := feed3.ReserveCluster(stCl, g_astFeedIo[3].rEnc, g_astFeedIo[3].rSpeed);
                    g_Disp.astClRsp[iD] := feed3.out_stCl;
                4: eRc := feed4.ReserveCluster(stCl, g_astFeedIo[4].rEnc, g_astFeedIo[4].rSpeed);
                    g_Disp.astClRsp[iD] := feed4.out_stCl;
                5: eRc := feed5.ReserveCluster(stCl, g_astFeedIo[5].rEnc, g_astFeedIo[5].rSpeed);
                    g_Disp.astClRsp[iD] := feed5.out_stCl;
                6: eRc := feed6.ReserveCluster(stCl, g_astFeedIo[6].rEnc, g_astFeedIo[6].rSpeed);
                    g_Disp.astClRsp[iD] := feed6.out_stCl;
                ELSE
                    (* Outfeeds never host cluster picks: refuse cleanly *)
                    g_Disp.astClRsp[iD].bOk := FALSE;
                    g_Disp.astClRsp[iD].bSync := FALSE;
                    g_Disp.astClRsp[iD].uiN := UINT#0;
            END_CASE
        ELSE
            CASE kD OF
                1: eRc := feed1.Reserve(stReq, g_astFeedIo[1].rEnc, g_astFeedIo[1].rSpeed);
                    g_Disp.astResRsp[iD] := feed1.out_stRes;
                2: eRc := feed2.Reserve(stReq, g_astFeedIo[2].rEnc, g_astFeedIo[2].rSpeed);
                    g_Disp.astResRsp[iD] := feed2.out_stRes;
                3: eRc := feed3.Reserve(stReq, g_astFeedIo[3].rEnc, g_astFeedIo[3].rSpeed);
                    g_Disp.astResRsp[iD] := feed3.out_stRes;
                4: eRc := feed4.Reserve(stReq, g_astFeedIo[4].rEnc, g_astFeedIo[4].rSpeed);
                    g_Disp.astResRsp[iD] := feed4.out_stRes;
                5: eRc := feed5.Reserve(stReq, g_astFeedIo[5].rEnc, g_astFeedIo[5].rSpeed);
                    g_Disp.astResRsp[iD] := feed5.out_stRes;
                6: eRc := feed6.Reserve(stReq, g_astFeedIo[6].rEnc, g_astFeedIo[6].rSpeed);
                    g_Disp.astResRsp[iD] := feed6.out_stRes;
                7: eRc := feed7.Reserve(stReq, g_astFeedIo[7].rEnc, g_astFeedIo[7].rSpeed);
                    g_Disp.astResRsp[iD] := feed7.out_stRes;
                ELSE
                    eRc := feed8.Reserve(stReq, g_astFeedIo[8].rEnc, g_astFeedIo[8].rSpeed);
                    g_Disp.astResRsp[iD] := feed8.out_stRes;
            END_CASE
        END_IF
        g_Disp.abResDone[iD] := TRUE;
    END_IF

    (* ----- 11b) Job offers -> robN.OfferJob ---------------------------- *)
    IF g_Disp.abJobPulse[iD] THEN
        g_Disp.abJobPulse[iD] := FALSE;     (* Consume the latched request *)
        CASE iD OF
            1: bRc := rob1.OfferJob(g_Disp.ajobOffer[1]);
            2: bRc := rob2.OfferJob(g_Disp.ajobOffer[2]);
            3: bRc := rob3.OfferJob(g_Disp.ajobOffer[3]);
            ELSE bRc := rob4.OfferJob(g_Disp.ajobOffer[4]);
        END_CASE
        IF NOT bRc THEN
            stRelJob := g_Disp.ajobOffer[iD];   (* Refused: release items *)
            bReleasePend := TRUE;
        END_IF
    END_IF

    (* ----- 11c) Job results -> close queue records + statistics -------- *)
    bResPend := FALSE;
    CASE iD OF
        1: IF rob1.bJobDone THEN stResJob := rob1.m_stJobRes; bResPend := TRUE; END_IF
        2: IF rob2.bJobDone THEN stResJob := rob2.m_stJobRes; bResPend := TRUE; END_IF
        3: IF rob3.bJobDone THEN stResJob := rob3.m_stJobRes; bResPend := TRUE; END_IF
        4: IF rob4.bJobDone THEN stResJob := rob4.m_stJobRes; bResPend := TRUE; END_IF
    END_CASE

    IF bResPend THEN
        FOR kD := 1 TO UINT_TO_DINT(stResJob.uiCount) DO
            stJI := stResJob.astItems[kD];

            IF stJI.bPick AND (stJI.iFeedPick >= 1) THEN
                bOk := (NOT stJI.bNg);
                CASE stJI.iFeedPick OF
                    1: eRc := feed1.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                    2: eRc := feed2.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                    3: eRc := feed3.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                    4: eRc := feed4.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                    5: eRc := feed5.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                    ELSE eRc := feed6.CompletePick(stJI.iIdx, bOk, g_astRobCfg[iD].uiRetries);
                END_CASE
                (* Statistics event -> ring (applied by PRG_SP_TaskMain) *)
                stEv.bCycle := FALSE; stEv.bPlace := FALSE;
                stEv.bOk := bOk; stEv.iFeed := stJI.iFeedPick;
                udiIdx := (GVL_SP_Sync.udiStatWr - GVL_SP_Sync.udiStatRd);
                IF udiIdx < UDINT#64 THEN
                    udiIdx := (GVL_SP_Sync.udiStatWr MOD UDINT#64) + UDINT#1;
                    GVL_SP_Sync.astStatEv[DINT_TO_DINT(udiIdx)] := stEv;
                    GVL_SP_Sync.udiStatWr := GVL_SP_Sync.udiStatWr + UDINT#1;
                ELSE
                    GVL_SP_Sync.udiStatDrop := GVL_SP_Sync.udiStatDrop + UDINT#1;
                END_IF
            END_IF

            IF stJI.bPlace AND (stJI.iFeedPlace >= 1) AND (NOT stJI.bNg) THEN
                CASE stJI.iFeedPlace OF
                    7: eRc := feed7.PlaceTarget(stJI.iIdxPlace);
                        eRc2 := patt1.NotifyPlaced(stJI.stItem.uiSlot);
                    8: eRc := feed8.PlaceTarget(stJI.iIdxPlace);
                        eRc2 := patt2.NotifyPlaced(stJI.stItem.uiSlot);
                    ELSE (* no pattern bookkeeping *)
                END_CASE
                (* Statistics event -> ring (applied by PRG_SP_TaskMain) *)
                stEv.bCycle := FALSE; stEv.bPlace := TRUE;
                stEv.bOk := (NOT stJI.bNg); stEv.iFeed := stJI.iFeedPlace;
                udiIdx := (GVL_SP_Sync.udiStatWr - GVL_SP_Sync.udiStatRd);
                IF udiIdx < UDINT#64 THEN
                    udiIdx := (GVL_SP_Sync.udiStatWr MOD UDINT#64) + UDINT#1;
                    GVL_SP_Sync.astStatEv[DINT_TO_DINT(udiIdx)] := stEv;
                    GVL_SP_Sync.udiStatWr := GVL_SP_Sync.udiStatWr + UDINT#1;
                ELSE
                    GVL_SP_Sync.udiStatDrop := GVL_SP_Sync.udiStatDrop + UDINT#1;
                END_IF
            END_IF
        END_FOR

        (* One cycle-complete event per closed job *)
        stEv.bCycle := TRUE; stEv.bPlace := FALSE;
        stEv.bOk := FALSE;   stEv.iFeed := 0;
        udiIdx := (GVL_SP_Sync.udiStatWr - GVL_SP_Sync.udiStatRd);
        IF udiIdx < UDINT#64 THEN
            udiIdx := (GVL_SP_Sync.udiStatWr MOD UDINT#64) + UDINT#1;
            GVL_SP_Sync.astStatEv[DINT_TO_DINT(udiIdx)] := stEv;
            GVL_SP_Sync.udiStatWr := GVL_SP_Sync.udiStatWr + UDINT#1;
        ELSE
            GVL_SP_Sync.udiStatDrop := GVL_SP_Sync.udiStatDrop + UDINT#1;
        END_IF

        g_Disp.astJobRes[iD] := stResJob;
        g_Disp.abJobResDone[iD] := TRUE;
    END_IF

    (* ----- 11d) Cancel requests -> release the partial job -------------- *)
    IF g_Disp.abCancelPulse[iD] THEN
        g_Disp.abCancelPulse[iD] := FALSE;  (* Consume the latched request *)
        stRelJob := g_Disp.astCancel[iD].stJob;
        bReleasePend := TRUE;
    END_IF
END_FOR

(* Release helper block (refusals and cancellations) *)
IF bReleasePend THEN
    FOR kD := 1 TO UINT_TO_DINT(stRelJob.uiCount) DO
        stJI := stRelJob.astItems[kD];
        IF stJI.bPick AND (stJI.iFeedPick >= 1) THEN
            CASE stJI.iFeedPick OF
                1: eRc := feed1.Release(stJI.iIdx);
                2: eRc := feed2.Release(stJI.iIdx);
                3: eRc := feed3.Release(stJI.iIdx);
                4: eRc := feed4.Release(stJI.iIdx);
                5: eRc := feed5.Release(stJI.iIdx);
                ELSE eRc := feed6.Release(stJI.iIdx);
            END_CASE
        END_IF
        IF stJI.bPlace AND (stJI.iFeedPlace >= 1) THEN
            CASE stJI.iFeedPlace OF
                7: eRc := feed7.Release(stJI.iIdxPlace);
                8: eRc := feed8.Release(stJI.iIdxPlace);
                ELSE (* nothing to release *)
            END_CASE
        END_IF
    END_FOR
    bReleasePend := FALSE;
END_IF

END_PROGRAM

