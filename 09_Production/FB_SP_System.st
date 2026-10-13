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
    (* Public configuration & commands (Main/HMI write) *)
    stSysCfg : ST_SP_SysCfg;
    (* Operator/System command register (start, stop, batch...) *)
    stCmd    : ST_SP_SysCmd;
    (* Batch start/abort pulses per outfeed 1..GC_FEEDS (set by BatchService, cleared by Main) *)
    aiPattStart : ARRAY[1..8] OF SINT;
    aiPattAbort : ARRAY[1..8] OF SINT;
END_VAR
VAR_OUTPUT
    stOut : ST_SP_SysStat;      (* Published system status *)
    (* Outputs to the wiring program *)
    abCamEnable : ARRAY[1..2] OF BOOL;   (* 1..GC_CAMS *)
    (* Conveyor enable vector staged by startup state 1..GC_FEEDS *)
    abConvEnable: ARRAY[1..8] OF BOOL;
    (* Dispatcher enable output (final stage) *)
    abDispatchOn: BOOL;
    (* Pause command per robot 1..GC_ROBOTS *)
    abRobPause  : ARRAY[1..4] OF BOOL;
    (* Resume command per robot 1..GC_ROBOTS *)
    abRobResume : ARRAY[1..4] OF BOOL;
    (* Fault-reset command per robot 1..GC_ROBOTS *)
    abRobReset  : ARRAY[1..4] OF BOOL;
    (* Dry-run command per robot 1..GC_ROBOTS *)
    abRobDryRun : ARRAY[1..4] OF BOOL;
    (* One-cycle pulse requesting queue purge on all tracking feeds *)
    bClearItemsPulse : BOOL;
    (* Published statistics mirrors from subordinate Stats *)
    stTot       : ST_SP_Counters;
    rPiecesPerH : LREAL;
    udiUptimeMs : UDINT;
    (* Batch query buffers from subordinate Batch *)
    out_stBatchDef  : ST_SP_BatchDef;
    out_stBatchStat : ST_SP_BatchStat;
END_VAR
VAR
    (* Subordinate managers *)
    Batch : SP_BatchMgr;        (* Batch registry *)
    Stats : SP_Stats;           (* Production statistics *)
    (* Startup staging *)
    m_uiStage : SINT := 0;      (* 0..3 *)
    m_tStage  : UDINT := 0;     (* Stage timer [ms] *)
    m_tStageDelay : UDINT := 500;
    (* Resiliency 1..GC_ROBOTS *)
    m_abRobDown : ARRAY[1..4] OF BOOL;
    (* Batch command handshake *)
    m_iStartBatchPrev : SINT := 0;
    (* Previous stop-batch command (edge detection) *)
    m_iStopBatchPrev  : SINT := 0;
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
Stats(
    uiDtMs := uiDtMs,
    bProd  := stOut.bRunning,
    stTot => stTot,
    out_stCnt => ,
    udiUptimeMs => udiUptimeMs,
    rPiecesPerH => rPiecesPerH
);
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
    bClearItemsPulse := stCmd.bClearItems;

    (* Clear one-cycle robot command pulses *)
    FOR i := 1 TO GC_ROBOTS DO
        abRobPause[i]  := FALSE;
        abRobResume[i] := FALSE;
        abRobReset[i]  := FALSE;
    END_FOR

    (* Robot health from the mirror *)
    uiRun := UINT#0; uiFault := UINT#0; udiItems := UDINT#0;
    FOR i := 1 TO GC_ROBOTS DO
        IF g_astRobStat[i].bFault OR (NOT g_astRobStat[i].bOnline) THEN
            m_abRobDown[i] := TRUE;
        ELSE
            m_abRobDown[i] := FALSE;
            uiRun := uiRun + UINT#1;
        END_IF
        IF g_astRobStat[i].bFault THEN
            uiFault := uiFault + UINT#1;
        END_IF
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        IF g_astFeedIo[i].bUsed THEN
            udiItems := udiItems + UINT_TO_UDINT(g_astFeedIo[i].stStat.uiTracked)
                        + UINT_TO_UDINT(g_astFeedIo[i].stStat.uiReserved);
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
                   IF (m_tStage >= m_tStageDelay) AND (uiRun > UINT#0) THEN
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
            (* Resiliency: any robot down -> Recovering if bResilience and a robot remains *)
            IF uiFault > UINT#0 THEN
                IF stSysCfg.bResilience AND (uiRun > UINT#0) THEN
                    THIS.OnRobotLoss();
                    m_eSt := ET_SP_SysState#Recovering;
                ELSE
                    m_uiErr := UINT#2;
                    m_eSt := ET_SP_SysState#Fault;
                END_IF
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
            IF stSysCfg.bStopConvsOnPause THEN
                FOR i := 1 TO GC_FEEDS DO
                    abConvEnable[i] := FALSE;
                END_FOR
            END_IF
            IF stCmd.bResume THEN
                m_eSt := ET_SP_SysState#Resuming;
            ELSIF stCmd.bStop THEN
                m_eSt := ET_SP_SysState#Stopping;
            END_IF

        ET_SP_SysState#Resuming:
            THIS.StageOutputs(3);
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
            THIS.BatchService();
            IF uiFault = UINT#0 THEN
                m_eSt := ET_SP_SysState#Running;   (* Cause resolved *)
            ELSIF (uiRun = UINT#0) OR (NOT stSysCfg.bResilience) THEN
                m_uiErr := UINT#2;                 (* No robot left *)
                m_eSt := ET_SP_SysState#Fault;
            ELSIF stCmd.bStop THEN
                m_eSt := ET_SP_SysState#Stopping;
            END_IF

        ET_SP_SysState#Fault:
            abDispatchOn := FALSE;
            THIS.StageOutputs(0);
            IF (stCmd.bReset OR (stSysCfg.bAutoRestart AND (uiFault = UINT#0))) AND bEStopOk THEN
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
            eRc := Batch.StartBatch(stCmd.iStartBatch);
            IF eRc = ET_SP_RetCode#Done THEN
                IF Batch.GetDef(stCmd.iStartBatch) THEN
                    iFeed := DINT_TO_SINT(FUN_SP_ClampI(SINT_TO_DINT(Batch.out_stDef.iOutFeed), 1, SINT_TO_DINT(GC_FEEDS)));
                    aiPattStart[iFeed] := stCmd.iStartBatch;  (* Pulse *)
                END_IF
            END_IF
        END_IF
    END_IF

    IF stCmd.iStopBatch <> m_iStopBatchPrev THEN
        m_iStopBatchPrev := stCmd.iStopBatch;
        IF stCmd.iStopBatch > 0 THEN
            Batch.StopBatch(stCmd.iStopBatch);
            IF Batch.GetDef(stCmd.iStopBatch) THEN
                iFeed := DINT_TO_SINT(FUN_SP_ClampI(SINT_TO_DINT(Batch.out_stDef.iOutFeed), 1, SINT_TO_DINT(GC_FEEDS)));
                aiPattAbort[iFeed] := stCmd.iStopBatch;
            END_IF
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SetBatch / GetBatchDef / GetBatchStat / GetActiveBatch /
           SyncBatchProgress (parent SP_System)
   Clean encapsulated wrappers over subordinate Batch (SP_BatchMgr).
   ----------------------------------------------------------------------- *)
METHOD SetBatch : ET_SP_RetCode
VAR_INPUT
    (* Batch table slot 1..GC_BATCHES *)
    iIdx  : SINT;
    (* Batch definition to store *)
    stDef : ST_SP_BatchDef;
END_VAR
    SetBatch := Batch.SetBatch(iIdx, stDef);
END_METHOD

METHOD GetBatchDef : BOOL
VAR_INPUT
    (* Batch table slot 1..GC_BATCHES *)
    iIdx : SINT;
END_VAR
    GetBatchDef := Batch.GetDef(iIdx);
    out_stBatchDef := Batch.out_stDef;
END_METHOD

METHOD GetBatchStat : BOOL
VAR_INPUT
    (* Batch table slot 1..GC_BATCHES *)
    iIdx : SINT;
END_VAR
    GetBatchStat := Batch.GetStat(iIdx);
    out_stBatchStat := Batch.out_stStat;
END_METHOD

METHOD GetActiveBatch : SINT
VAR_INPUT
    (* Outfeed selector 1..GC_FEEDS *)
    iOutFeed : SINT;
END_VAR
    GetActiveBatch := Batch.GetActive(iOutFeed);
END_METHOD

METHOD SyncBatchProgress : BOOL
VAR_INPUT
    (* Batch table slot 1..GC_BATCHES *)
    iIdx   : SINT;
    (* Pattern generator status snapshot *)
    stPatt : ST_SP_BatchStat;
END_VAR
    SyncBatchProgress := Batch.SyncProgress(iIdx, stPatt);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddPickStat / AddPlaceStat / AddCycleStat (parent SP_System)
   Clean encapsulated wrappers over subordinate Stats (SP_Stats).
   ----------------------------------------------------------------------- *)
METHOD AddPickStat : BOOL
VAR_INPUT
    (* TRUE = good pick *)
    bOk   : BOOL;
    (* Feed index 1..GC_FEEDS *)
    iFeed : SINT;
END_VAR
    AddPickStat := Stats.AddPick(bOk, iFeed);
END_METHOD

METHOD AddPlaceStat : BOOL
VAR_INPUT
    (* TRUE = good place *)
    bOk   : BOOL;
    (* Feed index 1..GC_FEEDS *)
    iFeed : SINT;
END_VAR
    AddPlaceStat := Stats.AddPlace(bOk, iFeed);
END_METHOD

METHOD AddCycleStat : BOOL
    AddCycleStat := Stats.AddCycle();
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
    uiRun := UINT#0; uiFault := UINT#0; udiItems := UDINT#0;
    FOR i := 1 TO GC_ROBOTS DO
        IF g_astRobStat[i].bOnline AND (NOT g_astRobStat[i].bFault) THEN
            uiRun := uiRun + UINT#1;
        END_IF
        IF g_astRobStat[i].bFault THEN
            uiFault := uiFault + UINT#1;
        END_IF
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        IF g_astFeedIo[i].bUsed THEN
            udiItems := udiItems + UINT_TO_UDINT(g_astFeedIo[i].stStat.uiTracked)
                        + UINT_TO_UDINT(g_astFeedIo[i].stStat.uiReserved);
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
