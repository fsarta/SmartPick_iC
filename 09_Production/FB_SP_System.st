(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 09_Production
   Worksheet : FB - SP_System
   -----------------------------------------------------------------------------
   Purpose   : System orchestrator (MotoPick 4 parity):

     - Synchronized startup: staged start (conveyors + cameras, robot
       readiness, dispatch) with configurable stage delay.
     - System locks: trial run (dry run) propagated to every robot.
     - Failure resiliency: robot loss handling (dispatch exclusion,
       camera control transfer, production continues with the remaining
       robots), recovery to Running when the cause is resolved.
     - Pause/resume of the whole system WITHOUT losing tracked items
       (queues keep encoder-based continuity).
     - Batch orchestration outputs toward the pattern generators.
     - Statistics ownership (public member Stats).

   NO references to other FBs (constraint): all cell state flows through
   the public mirror arrays (g_astRobStat / g_astFeedIo) written by
   PRG_SP_TaskMain. Subordinate managers (Bal, Batch, Stats) are public
   members so the wiring program can configure/drive them.
   =============================================================================
*)

FUNCTION_BLOCK SP_System
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    uiDtMs    : UDINT;          (* Task period [ms] *)
    bEStopOk  : BOOL;           (* Safety chain OK *)
END_VAR
VAR_OUTPUT
    stOut : ST_SP_SysStat;      (* Published system status *)
END_VAR
VAR
    (* Public configuration & commands (Main/HMI write) *)
    stSysCfg : ST_SP_SysCfg;
    (* Operator/System command register (start, stop, batch...) *)
    stCmd    : ST_SP_SysCmd;
    (* Public subordinate managers (wiring access allowed by design) *)
    Bal   : SP_LoadBalancer;    (* Distribution strategies *)
    Batch : SP_BatchMgr;        (* Batch registry *)
    Stats : SP_Stats;           (* Production statistics *)
    (* Startup staging *)
    m_uiStage : SINT := 0;      (* 0..3 *)
    m_tStage  : UDINT := 0;     (* Stage timer [ms] *)
    m_tStageDelay : UDINT := 500;
    (* Resiliency *)
    m_abRobDown : ARRAY[1..GC_ROBOTS] OF BOOL;
    (* Batch command handshake *)
    m_iStartBatchPrev : SINT := 0;
    (* Previous stop-batch command (edge detection) *)
    m_iStopBatchPrev  : SINT := 0;
    (* Outputs to the wiring program *)
    abCamEnable : ARRAY[1..GC_CAMS] OF BOOL;
    (* Conveyor enable vector staged by startup state *)
    abConvEnable: ARRAY[1..GC_FEEDS] OF BOOL;
    (* Dispatcher enable output (final stage) *)
    abDispatchOn: BOOL;
    (* Pause command per robot *)
    abRobPause  : ARRAY[1..GC_ROBOTS] OF BOOL;
    (* Resume command per robot *)
    abRobResume : ARRAY[1..GC_ROBOTS] OF BOOL;
    (* Fault-reset command per robot *)
    abRobReset  : ARRAY[1..GC_ROBOTS] OF BOOL;
    (* Dry-run command per robot *)
    abRobDryRun : ARRAY[1..GC_ROBOTS] OF BOOL;
    aiPattStart : ARRAY[1..GC_FEEDS] OF SINT;   (* Batch idx pulse per outfeed *)
    aiPattAbort : ARRAY[1..GC_FEEDS] OF SINT;
    (* System FSM state *)
    m_eSt : ET_SP_SysState := ET_SP_SysState#Init;
    (* Dry-run mode latched at start command *)
    m_bDryRunLatch : BOOL;
    (* System error code (0 = healthy) *)
    m_uiErr : UINT := 0;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
THIS.Step();
THIS.Publish();
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Step (parent SP_System) - internal
   System finite state machine.
   ----------------------------------------------------------------------- *)
METHOD Step : BOOL
VAR
    (* Robot loop index (publish scan) *)
    i : SINT;
    (* TRUE when every robot is idle (stop complete) *)
    bAllIdle : BOOL;
    (* TRUE when at least one robot exists/enabled *)
    bAnyRob : BOOL;
    (* Running-robot counter *)
    uiRun : UINT;
    (* Faulted-robot counter *)
    uiFault : UINT;
    (* Item total accumulated for publish *)
    udiItems : UDINT;
END_VAR
    Step := TRUE;                   (* System FSM step executed *)
    (* Stage delay from configuration (default 500 ms) *)
    m_tStageDelay := TIME_TO_UDINT(stSysCfg.tStartStage);
    IF m_tStageDelay = UDINT#0 THEN
        m_tStageDelay := UDINT#500;
    END_IF
    m_bDryRunLatch := stCmd.bDryRun;    (* Level command *)

    (* Robot health from the mirror *)
    uiRun := 0; uiFault := 0; udiItems := UDINT#0;
    FOR i := 1 TO GC_ROBOTS DO
        IF g_astRobStat[i].bFault OR (NOT g_astRobStat[i].bOnline) THEN
            m_abRobDown[i] := TRUE;
        ELSE
            m_abRobDown[i] := FALSE;
            uiRun := uiRun + 1;
        END_IF
        IF g_astRobStat[i].bFault THEN
            uiFault := uiFault + 1;
        END_IF
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        IF g_astFeedIo[i].bUsed THEN
            udiItems := udiItems + g_astFeedIo[i].stStat.uiTracked
                        + g_astFeedIo[i].stStat.uiReserved;
        END_IF
    END_FOR

    CASE m_eSt OF
        ET_SP_SysState#Init:
            abDispatchOn := FALSE;
            IF bEStopOk THEN
                m_eSt := ET_SP_SysState#Standby;
            END_IF

        ET_SP_SysState#Standby:
            abDispatchOn := FALSE;
            THIS.StageOutputs(0);
            IF stCmd.bStart AND bEStopOk THEN
                m_uiStage := 1;
                m_tStage := UDINT#0;
                m_eSt := ET_SP_SysState#Starting;
            END_IF

        ET_SP_SysState#Starting:
            (* Stage 1: conveyors + cameras, stage 2: robot enable/home,
               stage 3: dispatch + batch engines *)
            m_tStage := m_tStage + uiDtMs;
            CASE m_uiStage OF
                1: THIS.StageOutputs(1);
                   IF m_tStage >= m_tStageDelay THEN
                       m_uiStage := 2; m_tStage := UDINT#0;
                   END_IF
                2: THIS.StageOutputs(2);
                   IF (m_tStage >= m_tStageDelay) AND (uiRun > 0) THEN
                       m_uiStage := 3; m_tStage := UDINT#0;
                   END_IF
                3: THIS.StageOutputs(3);
                   abDispatchOn := TRUE;
                   m_eSt := ET_SP_SysState#Running;
            END_CASE

        ET_SP_SysState#Running:
            THIS.StageOutputs(3);
            abDispatchOn := TRUE;
            (* Batch commands *)
            THIS.BatchService();
            (* Resiliency: any robot down -> Recovering (continue or fault) *)
            IF uiFault > 0 THEN
                THIS.OnRobotLoss();
                m_eSt := ET_SP_SysState#Recovering;
            ELSIF stCmd.bPause THEN
                m_eSt := ET_SP_SysState#Pausing;
            ELSIF stCmd.bStop THEN
                m_eSt := ET_SP_SysState#Stopping;
            ELSIF NOT bEStopOk THEN
                m_uiErr := UINT#1;
                m_eSt := ET_SP_SysState#Fault;
            END_IF

        ET_SP_SysState#Pausing:
            abDispatchOn := FALSE;
            FOR i := 1 TO GC_ROBOTS DO
                abRobPause[i] := TRUE;
            END_FOR
            m_eSt := ET_SP_SysState#Paused;

        ET_SP_SysState#Paused:
            (* Items keep tracked; conveyors per policy *)
            FOR i := 1 TO GC_ROBOTS DO
                abRobPause[i] := FALSE;     (* pulse consumed by Main *)
            END_FOR
            IF stCmd.bResume THEN
                m_eSt := ET_SP_SysState#Resuming;
            ELSIF stCmd.bStop THEN
                m_eSt := ET_SP_SysState#Stopping;
            END_IF

        ET_SP_SysState#Resuming:
            FOR i := 1 TO GC_ROBOTS DO
                abRobResume[i] := TRUE;
            END_FOR
            m_eSt := ET_SP_SysState#Running;

        ET_SP_SysState#Stopping:
            abDispatchOn := FALSE;
            (* Graceful: wait robots idle, then stop conveyors/cameras *)
            bAllIdle := TRUE;
            FOR i := 1 TO GC_ROBOTS DO
                IF g_astRobStat[i].bBusy AND (NOT m_abRobDown[i]) THEN
                    bAllIdle := FALSE;
                END_IF
            END_FOR
            IF bAllIdle THEN
                THIS.StageOutputs(0);
                m_eSt := ET_SP_SysState#Stopped;
            END_IF

        ET_SP_SysState#Stopped:
            abDispatchOn := FALSE;
            THIS.StageOutputs(0);
            IF stCmd.bStart AND bEStopOk THEN
                m_eSt := ET_SP_SysState#Standby;   (* Arm again via Start *)
            END_IF

        ET_SP_SysState#Recovering:
            (* Production continues with the remaining robots (resiliency);
               camera control already transferred by OnRobotLoss. *)
            THIS.StageOutputs(3);
            abDispatchOn := TRUE;
            IF uiFault = 0 THEN
                m_eSt := ET_SP_SysState#Running;   (* Cause resolved *)
            ELSIF uiRun = 0 THEN
                m_uiErr := UINT#2;                 (* No robot left *)
                m_eSt := ET_SP_SysState#Fault;
            ELSIF stCmd.bStop THEN
                m_eSt := ET_SP_SysState#Stopping;
            END_IF

        ET_SP_SysState#Fault:
            abDispatchOn := FALSE;
            THIS.StageOutputs(0);
            IF stCmd.bReset AND bEStopOk THEN
                m_uiErr := UINT#0;
                FOR i := 1 TO GC_ROBOTS DO
                    abRobReset[i] := TRUE;
                END_FOR
                m_eSt := ET_SP_SysState#Standby;
            END_IF
    END_CASE

    (* Dry-run propagation *)
    FOR i := 1 TO GC_ROBOTS DO
        abRobDryRun[i] := m_bDryRunLatch;
    END_FOR

    (* Consume one-shot commands (FSM has evaluated them this cycle) *)
    stCmd.bStart := FALSE;
    stCmd.bStop := FALSE;
    stCmd.bPause := FALSE;
    stCmd.bResume := FALSE;
    stCmd.bReset := FALSE;
    stCmd.bClearItems := FALSE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StageOutputs (parent SP_System) - internal
   Enable vectors per startup stage (0=off, 1=conv+cam, 2=+robots, 3=all).
   ----------------------------------------------------------------------- *)
METHOD StageOutputs : BOOL
VAR_INPUT
    (* Startup stage to encode into enable vectors *)
    uiStage : SINT;
END_VAR
VAR
    (* Robot loop index (publish scan) *)
    i : SINT;
    (* Camera loop index (ownership check) *)
    k : SINT;
    (* TRUE when the camera owner robot is online *)
    bOwnerOk : BOOL;
END_VAR
    StageOutputs := TRUE;           (* Enable vectors staged *)
    FOR i := 1 TO GC_FEEDS DO
        abConvEnable[i] := (uiStage >= 1) AND g_astFeedIo[i].bUsed;
    END_FOR
    FOR k := 1 TO GC_CAMS DO
        abCamEnable[k] := (uiStage >= 1);
    END_FOR
    IF uiStage < 2 THEN
        FOR i := 1 TO GC_ROBOTS DO
            abRobPause[i] := FALSE;
            abRobResume[i] := FALSE;
            abRobReset[i] := FALSE;
        END_FOR
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: BatchService (parent SP_System) - internal
   Start/stop batch commands and per-outfeed pattern start pulses.
   ----------------------------------------------------------------------- *)
METHOD BatchService : BOOL
VAR
    (* Robot loop index (publish scan) *)
    i : SINT;
    (* Outfeed addressed by the batch command *)
    iFeed : SINT;
    (* Batch registry call result *)
    eRc : ET_SP_RetCode;
END_VAR
    BatchService := TRUE;           (* Batch commands serviced *)
    IF stCmd.iStartBatch <> m_iStartBatchPrev THEN
        m_iStartBatchPrev := stCmd.iStartBatch;
        IF stCmd.iStartBatch > 0 THEN
            eRc := THIS.Batch.StartBatch(stCmd.iStartBatch);
            IF eRc = ET_SP_RetCode#Done THEN
                IF THIS.Batch.GetDef(stCmd.iStartBatch) THEN
                    iFeed := FUN_SP_ClampI(THIS.Batch.out_stDef.iOutFeed, 1, GC_FEEDS);
                    aiPattStart[iFeed] := stCmd.iStartBatch;  (* Pulse *)
                END_IF
            END_IF
        END_IF
    END_IF

    IF stCmd.iStopBatch <> m_iStopBatchPrev THEN
        m_iStopBatchPrev := stCmd.iStopBatch;
        IF stCmd.iStopBatch > 0 THEN
            THIS.Batch.StopBatch(stCmd.iStopBatch);
            IF THIS.Batch.GetDef(stCmd.iStopBatch) THEN
                iFeed := FUN_SP_ClampI(THIS.Batch.out_stDef.iOutFeed, 1, GC_FEEDS);
                aiPattAbort[iFeed] := stCmd.iStopBatch;
            END_IF
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OnRobotLoss (parent SP_System) - internal
   Failure resiliency entry: mark down robots, transfer camera control
   ownership to the first remaining online robot configured as candidate.
   ----------------------------------------------------------------------- *)
METHOD OnRobotLoss : BOOL
VAR
    (* Camera/robot scan indices (iNew = new owner) *)
    i, k, iNew : SINT;
END_VAR
    OnRobotLoss := TRUE;            (* Resiliency entry executed *)
    FOR k := 1 TO GC_CAMS DO
        (* Current owner down? -> transfer *)
        iNew := 0;
        FOR i := 1 TO GC_ROBOTS DO
            IF (NOT m_abRobDown[i]) AND g_abCamOwnerCfg[k][i] THEN
                iNew := i;
                EXIT;
            END_IF
        END_FOR
        g_aiCamOwner[k] := iNew;    (* 0 = nobody available (cam stays on) *)
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Publish (parent SP_System) - internal
   ----------------------------------------------------------------------- *)
METHOD Publish : BOOL
VAR
    (* Robot loop index (publish scan) *)
    i : SINT;
    (* Running-robot counter *)
    uiRun : UINT;
    (* Faulted-robot counter *)
    uiFault : UINT;
    (* Item total accumulated for publish *)
    udiItems : UDINT;
END_VAR
    Publish := TRUE;                (* Status snapshot published *)
    uiRun := 0; uiFault := 0; udiItems := UDINT#0;
    FOR i := 1 TO GC_ROBOTS DO
        IF g_astRobStat[i].bOnline AND (NOT g_astRobStat[i].bFault) THEN
            uiRun := uiRun + 1;
        END_IF
        IF g_astRobStat[i].bFault THEN
            uiFault := uiFault + 1;
        END_IF
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        IF g_astFeedIo[i].bUsed THEN
            udiItems := udiItems + g_astFeedIo[i].stStat.uiTracked
                        + g_astFeedIo[i].stStat.uiReserved;
        END_IF
    END_FOR

    stOut.eState := m_eSt;
    stOut.bReady := (m_eSt = ET_SP_SysState#Running)
                    OR (m_eSt = ET_SP_SysState#Recovering);
    stOut.bRunning := (m_eSt = ET_SP_SysState#Running)
                      OR (m_eSt = ET_SP_SysState#Recovering);
    stOut.bPaused := (m_eSt = ET_SP_SysState#Paused);
    stOut.bDryRun := m_bDryRunLatch;
    stOut.uiRobotsRun := uiRun;
    stOut.uiRobotsFault := uiFault;
    stOut.udiItemsInSys := udiItems;
    stOut.uiErrId := m_uiErr;
END_METHOD
