(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : PROGRAM - PRG_SP_TaskMain (application task, ~10 ms)
   -----------------------------------------------------------------------------
   Purpose   : Application-layer program of the 3-task build (v1.6):
     - applies the configuration mid-layer (dispatcher/system part) and
       requests the motion-layer re-configure through GVL_SP_Sync.bCfgPend
     - decodes pattern batch start/stop pulses into the ST_SP_PattCmd
       mailbox consumed by PRG_SP_TaskFast
     - runs the dispatcher (SP_Dispatch.Run): the request side effects
       (feed.Reserve, rob.OfferJob, releases) are executed by
       PRG_SP_TaskFast on the latched request protocol
     - drains the production statistics event ring into SP_Stats
     - publishes the production counters snapshot for PRG_SP_TaskSvc
     - publishes one log request for PRG_SP_TaskSvc (single writer)

   Task assignment (iCube Engineer, see 00_TaskConfig_IT-EN.md):
     SP_Main_10ms  cyclic 10 ms, medium priority, watchdog 30 ms.
   Task-agnostic: assigning this program to the same task as the other two
   keeps identical semantics (one extra scan of mailbox latency).
   =============================================================================
*)

PROGRAM PRG_SP_TaskMain
VAR
    m_bInit : BOOL := TRUE;             (* First-scan boot latch *)
    iBatch  : SINT;                     (* Batch id under processing *)
    iD      : DINT;                     (* Robot loop index (sync grip) *)
    udiDlt  : UDINT;                    (* Statistics ring occupancy *)
    udiGuard: UDINT;                    (* Drain guard (max events/scan) *)
    eStEv   : ST_SP_StatEv;             (* Event under drain *)
    udiIdx  : UDINT;                    (* Ring slot index *)
    bRc     : BOOL;                     (* Boolean call result scratch *)
    eRc     : ET_SP_RetCode;            (* Enumerated call result scratch *)
END_VAR

(* =========================================================================
   1) CONFIGURATION APPLICATION (mid-layer: dispatcher + system)
      One-shot at boot and on every HMI re-apply pulse. The FB instances of
      the motion layer (conveyors, feeds, robots, cameras, pattern engines,
      guards) are re-configured by PRG_SP_TaskFast when bCfgPend arrives.
   ========================================================================= *)
IF m_bInit OR GVL_SP_Hmi.bApplyConfig THEN
    m_bInit := FALSE;
    GVL_SP_Hmi.bApplyConfig := FALSE;
    GVL_SP_Sync.bCfgPend   := TRUE;     (* -> TaskFast re-configure pulse *)

    eRc := g_Disp.Configure(g_stShareCfg);
    g_Disp.uiMaxGrip := g_astRobCfg[1].uiMaxGrip;   (* System-wide multi-grip *)
    g_Sys.stSysCfg := g_stSysCfg;

    (* Load batch definitions into the system batch registry *)
    FOR iD := 1 TO SINT_TO_DINT(GC_BATCHES) DO
        eRc := g_Sys.SetBatch(DINT_TO_SINT(iD), g_astBatchDef[iD]);
    END_FOR

    (* Populate camera ownership matrix for resiliency (OnRobotLoss) *)
    FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
        g_abCamOwnerCfg[1][iD] := g_astRobCfg[iD].abiCamOwner[1];
        g_abCamOwnerCfg[2][iD] := g_astRobCfg[iD].abiCamOwner[2];
    END_FOR

    (* R-07: per-robot synchronized multi-grip enable for the dispatcher *)
    FOR iD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
        g_Disp.abSyncGrip[iD] := (g_astRobCfg[iD].eGripMode = ET_SP_GripMode#Sync)
                                 AND (g_astRobCfg[iD].uiMaxGrip > UINT#1)
                                 AND (g_astRobCfg[iD].astTools[1].rMatchTol > 0.0);
    END_FOR

    (* Log request -> PRG_SP_TaskSvc (single-writer mailbox, avoids a
       cross-task call into the ring logger) *)
    GVL_SP_Sync.sLogMsg  := 'Configuration applied';
    GVL_SP_Sync.bLogPend := TRUE;
END_IF

(* =========================================================================
   2) PATTERN BATCH COMMANDS (mid-layer decode -> mailbox)
      SP_System publishes aiPattStart/aiPattAbort pulses (batch registry
      resolved in THIS task); the motion task executes them on patt1/patt2
      through StartBatch(stDef, stPatt, udiBatchId) / AbortBatch.
      Mailbox indices: 1 = outfeed 7 (patt1), 2 = outfeed 8 (patt2).
   ========================================================================= *)
(* Start commands: resolve def + pattern + runtime id here, latch mailbox *)
IF g_Sys.aiPattStart[7] > 0 THEN
    iBatch := g_Sys.aiPattStart[7];
    g_Sys.aiPattStart[7] := 0;          (* Consume the pulse (owner task) *)
    bRc := g_Sys.GetBatchDef(iBatch);
    IF bRc THEN
        iD := UINT_TO_DINT(g_Sys.out_stBatchDef.uiPattId);
        bRc := g_Sys.GetBatchStat(iBatch);
        GVL_SP_Sync.stPattCmd[1].stDef      := g_Sys.out_stBatchDef;
        GVL_SP_Sync.stPattCmd[1].stPatt     := g_astPatt[iD];
        GVL_SP_Sync.stPattCmd[1].udiBatchId := g_Sys.out_stBatchStat.udiBatchId;
        GVL_SP_Sync.stPattCmd[1].iBatch     := iBatch;
        GVL_SP_Sync.stPattCmd[1].iFeed      := 7;
        GVL_SP_Sync.stPattCmd[1].bStart     := TRUE;   (* Latched request *)
    END_IF
END_IF
IF g_Sys.aiPattStart[8] > 0 THEN
    iBatch := g_Sys.aiPattStart[8];
    g_Sys.aiPattStart[8] := 0;
    bRc := g_Sys.GetBatchDef(iBatch);
    IF bRc THEN
        iD := UINT_TO_DINT(g_Sys.out_stBatchDef.uiPattId);
        bRc := g_Sys.GetBatchStat(iBatch);
        GVL_SP_Sync.stPattCmd[2].stDef      := g_Sys.out_stBatchDef;
        GVL_SP_Sync.stPattCmd[2].stPatt     := g_astPatt[iD];
        GVL_SP_Sync.stPattCmd[2].udiBatchId := g_Sys.out_stBatchStat.udiBatchId;
        GVL_SP_Sync.stPattCmd[2].iBatch     := iBatch;
        GVL_SP_Sync.stPattCmd[2].iFeed      := 8;
        GVL_SP_Sync.stPattCmd[2].bStart     := TRUE;
    END_IF
END_IF

(* Abort commands: latched like the starts; when both are pending the
   fast task executes StartBatch then AbortBatch (same order as v1.5,
   where the two pulse blocks ran in this sequence in one scan) *)
IF g_Sys.aiPattAbort[7] > 0 THEN
    GVL_SP_Sync.stPattCmd[1].bAbort := TRUE;
    GVL_SP_Sync.stPattCmd[1].iBatch := g_Sys.aiPattAbort[7];
    g_Sys.aiPattAbort[7] := 0;
END_IF
IF g_Sys.aiPattAbort[8] > 0 THEN
    GVL_SP_Sync.stPattCmd[2].bAbort := TRUE;
    GVL_SP_Sync.stPattCmd[2].iBatch := g_Sys.aiPattAbort[8];
    g_Sys.aiPattAbort[8] := 0;
END_IF

(* Batch progress: consume the pattern status published by the fast task *)
iBatch := g_Sys.GetActiveBatch(7);
IF iBatch > 0 THEN bRc := g_Sys.SyncBatchProgress(iBatch, GVL_SP_Sync.stPattStat[1]); END_IF
iBatch := g_Sys.GetActiveBatch(8);
IF iBatch > 0 THEN bRc := g_Sys.SyncBatchProgress(iBatch, GVL_SP_Sync.stPattStat[2]); END_IF

(* =========================================================================
   3) DISPATCHER (decision layer)
      Run() refreshes the balancer snapshot, assigns feeds to idle robots
      and advances the per-robot handshakes. The request side effects run
      in PRG_SP_TaskFast (latched requests, latched responses).
   ========================================================================= *)
g_Disp.bEnable := g_Sys.abDispatchOn;
bRc := g_Disp.Run();

(* =========================================================================
   3b) SYSTEM ORCHESTRATOR + COMMAND WIRING
      Consumes the HMI one-shot commands (single consumer: THIS task) and
      advances the staged startup / resiliency / batch service FSM. The
      dispatch gate published here is consumed by section 3 next scan
      (same one-cycle contract as the v1.5 single-task build).
   ========================================================================= *)
g_Sys.stCmd.bStart    := g_hmiCmd.bStart;
g_Sys.stCmd.bStop     := g_hmiCmd.bStop;
g_Sys.stCmd.bPause    := g_hmiCmd.bPause;
g_Sys.stCmd.bResume   := g_hmiCmd.bResume;
g_Sys.stCmd.bReset    := g_hmiCmd.bReset;
g_Sys.stCmd.bDryRun   := g_hmiCmd.bDryRun;
g_Sys.stCmd.bClearItems := g_hmiCmd.bClearItems;
g_Sys.stCmd.iStartBatch := g_hmiCmd.iStartBatch;
g_Sys.stCmd.iStopBatch  := g_hmiCmd.iStopBatch;
g_hmiCmd.bStart := FALSE;
g_hmiCmd.bStop := FALSE;
g_hmiCmd.bPause := FALSE;
g_hmiCmd.bResume := FALSE;
g_hmiCmd.bReset := FALSE;
g_hmiCmd.bClearItems := FALSE;

g_Sys(uiDtMs := GVL_SP_Sync.uiMainDtMs,
      bEStopOk := GVL_SP_Io.bEStopOk AND GVL_SP_Io.bSafetyOk);

(* =========================================================================
   4) STATISTICS EVENT RING DRAIN (fast -> Stats)
      PRG_SP_TaskFast pushes one event per pick / place / cycle; this task
      applies them to SP_Stats (single writer of the counters). UDINT
      cursors wrap safely with modular subtraction.
   ========================================================================= *)
udiDlt := GVL_SP_Sync.udiStatWr - GVL_SP_Sync.udiStatRd;
udiGuard := UDINT#0;
WHILE (udiDlt > UDINT#0) AND (udiGuard < UDINT#64) DO
    udiIdx := (GVL_SP_Sync.udiStatRd MOD UDINT#64) + UDINT#1;
    eStEv  := GVL_SP_Sync.astStatEv[UDINT_TO_DINT(udiIdx)];
    GVL_SP_Sync.udiStatRd := GVL_SP_Sync.udiStatRd + UDINT#1;
    udiGuard := udiGuard + UDINT#1;
    udiDlt  := GVL_SP_Sync.udiStatWr - GVL_SP_Sync.udiStatRd;

    IF eStEv.bCycle THEN
        bRc := g_Sys.AddCycleStat();
    ELSIF eStEv.bPlace THEN
        bRc := g_Sys.AddPlaceStat(eStEv.bOk, eStEv.iFeed);
    ELSE
        bRc := g_Sys.AddPickStat(eStEv.bOk, eStEv.iFeed);
    END_IF
END_WHILE

(* =========================================================================
   5) PUBLICATIONS FOR PRG_SP_TaskSvc
      Counters snapshot (HMI-grade: cosmetic tear acceptable, never used
      for control) - single writer, written once per scan.
   ========================================================================= *)
GVL_SP_Sync.stTotPub := g_Sys.stTot;
GVL_SP_Sync.rPphPub  := g_Sys.rPiecesPerH;

END_PROGRAM
