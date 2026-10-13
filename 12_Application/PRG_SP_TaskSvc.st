(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : PROGRAM - PRG_SP_TaskSvc (service task, ~100 ms)
   -----------------------------------------------------------------------------
   Purpose   : Service-layer program of the 3-task build (v1.6). Everything
               that may block or jitter (file I/O on flash, string building,
               HMI mirror copying, KPI math) lives HERE, far away from the
               2 ms motion loop:
     - real-time clock: wall clock from Y_YA_RealTimeClock (Y_Yaskawa
       Toolbox), tick-derived fallback for simulation / RTC failure
     - OEE / KPI engine, predictive maintenance, startup self-test
     - collision guard diagnostics + separation stop alarms (edges from the
       HMI mirror published by PRG_SP_TaskFast)
     - ring logger, alarm registry, retain blob, CSV recipe backup FSM,
       log dump on demand, alarm acknowledge
     - HMI service mirrors (alarms, log, OEE, maintenance, self-test, stats)
     - consumes the log request mailbox of PRG_SP_TaskMain

   Task assignment (iCube Engineer, see 00_TaskConfig_IT-EN.md):
     SP_Svc_100ms  cyclic 100 ms, low priority, watchdog 500 ms.
   Task-agnostic: assigning this program to the same task as the other two
   keeps identical semantics.
   =============================================================================
*)

PROGRAM PRG_SP_TaskSvc
VAR
    (* --------------------------- Instances ------------------------------ *)
    (* OEE / KPI engine (R-16) *)
    oee      : SP_Oee;
    (* Predictive maintenance counters (R-16) *)
    g_Maint  : SP_Maint;
    (* Startup self-test suite (R-16) *)
    g_Test   : SP_SelfTest;
    (* Ring-buffer logger (single writer: this task) *)
    g_Log    : SP_Logger;
    (* Central alarm registry *)
    g_Alm    : SP_AlarmMgr;
    (* Retain blob manager (power-failure continuity) *)
    g_Retain : SP_RetainMgr;
    (* CSV recipe import/export manager (optional backup format) *)
    g_Recipy : SP_RecipeMgr;
    (* File adapter (recipe + log files, ADR confined) *)
    g_File   : SP_FileIo;

    (* --------------------------- Locals ---------------------------------- *)
    aRobPicks : ARRAY[1..GC_ROBOTS] OF UDINT;   (* Maintenance mirror: picks *)
    aCamTrig  : ARRAY[1..GC_CAMS] OF UDINT;     (* Maintenance mirror: shots *)
    (* R-16: alarm edge latches (raise once, clear on recovery) *)
    m_bMaintAlm : BOOL := FALSE;
    m_bTestAlm  : BOOL := FALSE;            (* Prev-scan self-test alarm edge *)
    m_abSepAlm  : ARRAY[1..GC_ROBOTS] OF BOOL; (* Separation-stop edge mirrors *)
    (* Recipe save / load state (0=idle 1=saving 2=loading) *)
    m_iRcpSt  : SINT := 0;
    m_iRcpIdle: SINT := 0;                  (* EOF detect counter (loading) *)
    m_iLogSt  : SINT := 0;                  (* 0=idle 1=writing *)
    m_iLogN   : DINT := 0;                  (* Log dump line cursor *)
    m_bFileClose : BOOL := FALSE;           (* Deferred file close request *)
    bRc       : BOOL;                       (* Boolean call result scratch *)
    kD        : DINT;                       (* General loop index *)
END_VAR

(* =========================================================================
   1) REAL-TIME CLOCK (v1.8.0)
      Vendor binding Y_YA_RealTimeClock (Y_Yaskawa_Toolbox library): the
      wall clock feeds every timestamp of the service layer (log entries,
      alarm raise/clear, self-test run stamp) and the HMI clock display.
      Simulation / RTC failure fallback: derive the wall clock from the
      monotonic tick (FUN_SP_TickToRtc) so offline runs stay deterministic.
      Durations NEVER come from here: PRG_SP_TaskFast owns g_udiTickMs.
   ========================================================================= *)
g_FBRTC(Enable := TRUE);
g_bRtcValid := g_FBRTC.Valid;
g_uiRtcErr  := g_FBRTC.ErrorID;
IF g_bSim OR (NOT g_FBRTC.Valid) THEN
    g_stRtcNow := FUN_SP_TickToRtc(g_udiTickMs);
ELSE
    g_stRtcNow := g_FBRTC.Clock;
END_IF
g_sRtcNow := FUN_SP_RtcToStr(g_stRtcNow);

(* =========================================================================
   2) LOG REQUEST MAILBOX (PRG_SP_TaskMain -> here)
      The application task cannot call the ring logger directly (different
      task); it latches a message here.
   ========================================================================= *)
IF GVL_SP_Sync.bLogPend THEN
    GVL_SP_Sync.bLogPend := FALSE;
    g_Log.LogInfo(ET_SP_LogSource#System, GVL_SP_Sync.sLogMsg);
END_IF

(* =========================================================================
   3) OEE / KPI ENGINE (R-16)
      Inputs come from task-published snapshots: g_hmiSysStat (fast task)
      and GVL_SP_Sync.stTotPub (application task).
   ========================================================================= *)
oee(uiDtMs := GVL_SP_Sync.uiSvcDtMs,
    bShift := GVL_SP_Hmi.g_hmiSysStat.bRunning OR GVL_SP_Hmi.g_hmiSysStat.bPaused,
    bFault := (GVL_SP_Hmi.g_hmiSysStat.uiRobotsFault > UINT#0),
    stCnt := GVL_SP_Sync.stTotPub,
    rIdealCycleMs := GVL_SP_Hmi.rIdealCycleMs);
IF GVL_SP_Hmi.bShiftReset THEN
    GVL_SP_Hmi.bShiftReset := FALSE;
    oee.Reset(GVL_SP_Sync.stTotPub);
END_IF
GVL_SP_Hmi.g_stHmiOee := oee.stView;

(* =========================================================================
   4) PREDICTIVE MAINTENANCE (R-16)
      Lifetime mirrors come from the fast-task HMI publications.
   ========================================================================= *)
aRobPicks[1] := GVL_SP_Hmi.g_astHmiRob[1].udiPicks;
aRobPicks[2] := GVL_SP_Hmi.g_astHmiRob[2].udiPicks;
aRobPicks[3] := GVL_SP_Hmi.g_astHmiRob[3].udiPicks;
aRobPicks[4] := GVL_SP_Hmi.g_astHmiRob[4].udiPicks;
aCamTrig[1] := GVL_SP_Hmi.g_astHmiCam[1].udiTriggers;
aCamTrig[2] := GVL_SP_Hmi.g_astHmiCam[2].udiTriggers;
g_Maint(uiDtMs := GVL_SP_Sync.uiSvcDtMs, bPumpOn := GVL_SP_Hmi.g_hmiSysStat.bRunning,
        stCfg := g_stMaintCfg, audiRobPicks := aRobPicks,
        audiCamTrig := aCamTrig, abConvRun := g_abConvRun);
IF GVL_SP_Hmi.bMaintReset THEN
    GVL_SP_Hmi.bMaintReset := FALSE;
    g_Maint.ResetAll();
END_IF
GVL_SP_Hmi.g_stHmiMaint := g_Maint.stStat;
IF g_Maint.stStat.bAnyDue AND (NOT m_bMaintAlm) THEN
    m_bMaintAlm := TRUE;
    g_Alm.Raise(UINT#40, ET_SP_LogSource#System, ET_SP_LogLevel#Warn,
                'Maintenance due: schedule a service intervention');
ELSIF (NOT g_Maint.stStat.bAnyDue) AND m_bMaintAlm THEN
    m_bMaintAlm := FALSE;
    g_Alm.Clear(UINT#40);
END_IF

(* =========================================================================
   5) STARTUP SELF-TEST (R-16)
   ========================================================================= *)
g_Test(bRun := GVL_SP_Hmi.bRunSelfTest, stNow := g_stRtcNow);
GVL_SP_Hmi.bRunSelfTest := FALSE;
GVL_SP_Hmi.g_stHmiTest := g_Test.stRes;
IF (NOT g_Test.stRes.bPass) AND (g_Test.stRes.uiChecks > UINT#0) AND (NOT m_bTestAlm) THEN
    m_bTestAlm := TRUE;
    g_Alm.Raise(UINT#41, ET_SP_LogSource#System, ET_SP_LogLevel#Error,
                'Self-test failed: check the diagnostics page');
ELSIF g_Test.stRes.bPass AND m_bTestAlm THEN
    m_bTestAlm := FALSE;
    g_Alm.Clear(UINT#41);
END_IF

(* =========================================================================
   6) COLLISION GUARD DIAGNOSTICS + SEPARATION ALARMS (R-05b)
      Source is the fast-task publication GVL_SP_Hmi.g_astHmiCol (single
      writer, one scan old at worst - irrelevant at alarm grade).
   ========================================================================= *)
FOR kD := 1 TO SINT_TO_DINT(GC_ROBOTS) DO
    IF (GVL_SP_Hmi.g_astHmiCol[kD].eWhy = ET_SP_ColAct#SepStop) AND (NOT m_abSepAlm[kD]) THEN
        m_abSepAlm[kD] := TRUE;
        g_Alm.Raise(DINT_TO_UINT(30 + kD - 1), ET_SP_LogSource#Robot,
                    ET_SP_LogLevel#Error,
                    'Robot separation stop: check the shared zone');
    ELSIF (GVL_SP_Hmi.g_astHmiCol[kD].eWhy <> ET_SP_ColAct#SepStop) AND m_abSepAlm[kD] THEN
        m_abSepAlm[kD] := FALSE;
        g_Alm.Clear(DINT_TO_UINT(30 + kD - 1));
    END_IF
END_FOR

(* =========================================================================
   7) SERVICES: file, logger, alarms, retain
   ========================================================================= *)
g_File(bCloseReq := m_bFileClose);
m_bFileClose := FALSE;

g_Log(stNow := g_stRtcNow);
g_Alm(stNow := g_stRtcNow);
g_Retain();

(* =========================================================================
   8) RECIPE SAVE / LOAD (optional CSV backup; one line per scan,
      non-blocking style - state machine is owned by THIS task)
   ========================================================================= *)
IF GVL_SP_Hmi.bSaveRecipe AND (m_iRcpSt = 0) THEN
    GVL_SP_Hmi.bSaveRecipe := FALSE;
    g_Recipy.ExportBegin(GVL_SP_Hmi.sRecipeName);
    bRc := g_File.OpenWrite(CONCAT('/recipes/', CONCAT(GVL_SP_Hmi.sRecipeName, '.csv')));
    IF bRc THEN
        m_iRcpSt := 1;
        GVL_SP_Hmi.sHmiRecipeState := 'saving...';
    ELSE
        GVL_SP_Hmi.sHmiRecipeState := 'save error';
        g_Log.LogError(ET_SP_LogSource#Persist, 1, 'Recipe open for write failed');
    END_IF
END_IF

IF GVL_SP_Hmi.bLoadRecipe AND (m_iRcpSt = 0) THEN
    GVL_SP_Hmi.bLoadRecipe := FALSE;
    bRc := g_File.OpenRead(CONCAT('/recipes/', CONCAT(GVL_SP_Hmi.sRecipeName, '.csv')));
    IF bRc THEN
        m_iRcpSt := 2;
        m_iRcpIdle := 0;
        GVL_SP_Hmi.sHmiRecipeState := 'loading...';
    ELSE
        GVL_SP_Hmi.sHmiRecipeState := 'load error';
        g_Log.LogError(ET_SP_LogSource#Persist, 1, 'Recipe open for read failed');
    END_IF
END_IF

CASE m_iRcpSt OF
    1: (* Saving *)
        IF g_Recipy.ExportNext() THEN
            bRc := g_File.WriteLine(g_Recipy.out_sLine);
            IF NOT bRc THEN
                m_iRcpSt := 0;
                m_bFileClose := TRUE;
                GVL_SP_Hmi.sHmiRecipeState := 'save write error';
            END_IF
        ELSE
            m_iRcpSt := 0;
            m_bFileClose := TRUE;
            GVL_SP_Hmi.sHmiRecipeState := 'saved';
            g_Retain.SetRecipe(GVL_SP_Hmi.sRecipeName);
            g_Log.LogInfo(ET_SP_LogSource#Persist, 'Recipe saved');
        END_IF

    2: (* Loading *)
        IF g_File.bLineRdy THEN
            m_iRcpIdle := 0;
            bRc := g_Recipy.ImportLine(g_File.out_sLine);
            IF g_Recipy.bErr THEN
                g_Log.LogWarn(ET_SP_LogSource#Persist, 'Recipe line rejected');
            END_IF
        ELSE
            m_iRcpIdle := m_iRcpIdle + 1;
            IF m_iRcpIdle > 10 THEN
                m_iRcpSt := 0;
                m_bFileClose := TRUE;
                GVL_SP_Hmi.bApplyConfig := TRUE;   (* Re-apply to all FBs *)
                GVL_SP_Hmi.sHmiRecipeState := 'loaded';
                g_Retain.SetRecipe(GVL_SP_Hmi.sRecipeName);
                g_Log.LogInfo(ET_SP_LogSource#Persist, 'Recipe loaded');
            END_IF
        END_IF
END_CASE

(* =========================================================================
   9) LOG DUMP ON DEMAND
   ========================================================================= *)
IF GVL_SP_Hmi.bExportLog AND (m_iLogSt = 0) THEN
    GVL_SP_Hmi.bExportLog := FALSE;
    bRc := g_File.OpenWrite('/recipes/smartpick_log.txt');
    IF bRc THEN
        m_iLogSt := 1;
        m_iLogN := SINT_TO_DINT(64);   (* Dump the newest 64 entries *)
    END_IF
END_IF

CASE m_iLogSt OF
    1: IF m_iLogN >= 1 THEN
            bRc := g_Log.ExportLine(DINT_TO_UINT(m_iLogN));
            IF bRc THEN
                bRc := g_File.WriteLine(g_Log.out_stEntry.sText);
            END_IF
            m_iLogN := m_iLogN - 1;
        ELSE
            m_iLogSt := 0;
            m_bFileClose := TRUE;
            g_Log.LogInfo(ET_SP_LogSource#System, 'Log dump completed');
        END_IF
END_CASE

(* =========================================================================
   10) ALARM ACKNOWLEDGE + HMI SERVICE MIRRORS
   ========================================================================= *)
IF GVL_SP_Hmi.bAckAll THEN
    GVL_SP_Hmi.bAckAll := FALSE;
    g_Alm.AckAll();
END_IF

(* Production totals (application-task snapshot) *)
GVL_SP_Hmi.g_stHmiStats := GVL_SP_Sync.stTotPub;
GVL_SP_Hmi.rHmiPiecesPerH := GVL_SP_Sync.rPphPub;

FOR kD := 1 TO 8 DO
    bRc := g_Alm.GetEntry(DINT_TO_UINT(kD));
    IF bRc THEN
        GVL_SP_Hmi.g_astHmiAlarm[kD] := g_Alm.out_stAlarm;
    ELSE
        GVL_SP_Hmi.g_astHmiAlarm[kD].eState := ET_SP_AckState#Inactive;
    END_IF
    bRc := g_Log.GetEntry(DINT_TO_UINT(kD));
    IF bRc THEN
        GVL_SP_Hmi.g_astHmiLog[kD] := g_Log.out_stEntry;
    ELSE
        GVL_SP_Hmi.g_astHmiLog[kD].sText := '';
    END_IF
END_FOR

END_PROGRAM
