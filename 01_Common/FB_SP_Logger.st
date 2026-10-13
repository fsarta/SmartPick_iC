(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FB - SP_Logger
   -----------------------------------------------------------------------------
   Purpose   : Comprehensive ring-buffer logger with severity levels and
               source tags. Entries are time-stamped by the caller-supplied
               RTC snapshot (Yt_YA_RTC_Struct, single source pattern, see
               GVL_SP_Rtc / PRG_SP_TaskSvc - v1.8.0 replaced the IEC DT).
               File export is performed by the System orchestrator through
               SP_FileIo (keeps ADR()/file usage confined to the adapter).
   -----------------------------------------------------------------------------
   Methods   : Log        : UDINT - add one entry (explicit level), seq
               LogInfo / LogWarn / LogError : UDINT - wrappers
               GetEntry   : BOOL - copy entry i (1 = newest)
               ExportLine : BOOL - format entry i as ASCII dump line
               Clear      : UINT - drop all entries, count dropped
   -----------------------------------------------------------------------------
   Concurrency: single writer per cycle (System), lock-free by design.
   =============================================================================
*)

FUNCTION_BLOCK SP_Logger
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    stNow : Yt_YA_RTC_Struct;         (* Wall clock stamp (from TaskSvc) *)
END_VAR
VAR_OUTPUT
    uiCount : UINT;                   (* Entries currently stored *)
    udiSeq  : UDINT;                  (* Total entries ever logged *)
    out_stEntry : ST_SP_LogEntry;     (* Result buffer of GetEntry/ExportLine *)
END_VAR
VAR
    m_astBuf : ARRAY[1..256] OF ST_SP_LogEntry;  (* Ring buffer 1..GC_LOG_N *)
    m_iHead  : UINT := 1;             (* Next write slot (1-based) *)
    m_iCnt   : UINT := 0;             (* Stored entries *)
    m_udiSeq : UDINT := 0;            (* Sequence generator *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Passive FB: entries are added through methods. Body publishes counters. *)
uiCount := m_iCnt;
udiSeq  := m_udiSeq;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Log (parent SP_Logger)
   Add one entry with explicit level. Overwrites the oldest entry when full.
   ----------------------------------------------------------------------- *)
METHOD Log : UDINT
VAR_INPUT
    (* Severity of the entry (Debug/Info/Warn/Error) *)
    eLevel : ET_SP_LogLevel;
    (* Originating module tag *)
    eSrc   : ET_SP_LogSource;
    (* Module-specific event/alarm code (0 = none) *)
    uiCode : UINT;
    (* Message text (without level/code) *)
    sText  : STRING(120);
END_VAR
VAR
    (* Write slot computed from ring head *)
    iW : UINT;
END_VAR
    iW := m_iHead;

    m_astBuf[iW].udiSeq := m_udiSeq + 1;
    m_astBuf[iW].stTime := stNow;
    m_astBuf[iW].eLevel := eLevel;
    m_astBuf[iW].eSrc   := eSrc;
    m_astBuf[iW].uiCode := uiCode;
    m_astBuf[iW].sText  := sText;

    m_iHead := m_iHead + 1;
    IF m_iHead > GC_LOG_N THEN
        m_iHead := 1;
    END_IF
    IF m_iCnt < GC_LOG_N THEN
        m_iCnt := m_iCnt + 1;
    END_IF

    m_udiSeq := m_udiSeq + 1;
    uiCount  := m_iCnt;
    udiSeq   := m_udiSeq;
    Log := m_udiSeq;                (* Sequence number of the entry *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: LogInfo (parent SP_Logger)
   Convenience wrapper, Info level.
   ----------------------------------------------------------------------- *)
METHOD LogInfo : UDINT
VAR_INPUT
    (* Originating module tag *)
    eSrc  : ET_SP_LogSource;
    (* Message text *)
    sText : STRING(120);
END_VAR
    LogInfo := THIS.Log(ET_SP_LogLevel#Info, eSrc, 0, sText);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: LogWarn (parent SP_Logger)
   Convenience wrapper, Warn level.
   ----------------------------------------------------------------------- *)
METHOD LogWarn : UDINT
VAR_INPUT
    (* Originating module tag *)
    eSrc  : ET_SP_LogSource;
    (* Message text *)
    sText : STRING(120);
END_VAR
    LogWarn := THIS.Log(ET_SP_LogLevel#Warn, eSrc, 0, sText);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: LogError (parent SP_Logger)
   Convenience wrapper, Error level with module code.
   ----------------------------------------------------------------------- *)
METHOD LogError : UDINT
VAR_INPUT
    (* Originating module tag *)
    eSrc  : ET_SP_LogSource;
    (* Error code shown beside the message *)
    uiCode: UINT;
    (* Message text *)
    sText : STRING(120);
END_VAR
    LogError := THIS.Log(ET_SP_LogLevel#Error, eSrc, uiCode, sText);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetEntry (parent SP_Logger)
   Copy entry iIdx (1 = newest) into out_stEntry. TRUE on success.
   Ring layout: next write = m_iHead; newest stored at m_iHead - 1.
   ----------------------------------------------------------------------- *)
METHOD GetEntry : BOOL
VAR_INPUT
    iIdx : UINT;    (* 1-based, 1 = newest *)
END_VAR
VAR
    (* Physical ring index derived from head and iIdx *)
    iPhys : UINT;
END_VAR
    GetEntry := FALSE;
    IF (iIdx >= 1) AND (iIdx <= m_iCnt) THEN
        iPhys := m_iHead + GC_LOG_N;  (* avoid unsigned underflow *)
        iPhys := iPhys - iIdx;
        IF iPhys > GC_LOG_N THEN
            iPhys := iPhys - GC_LOG_N;
        END_IF
        IF iPhys = 0 THEN
            iPhys := GC_LOG_N;
        END_IF
        out_stEntry := m_astBuf[iPhys];
        GetEntry := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExportLine (parent SP_Logger)
   Format entry iIdx (1 = newest) as one ASCII line into out_stEntry.sText.
   Format: <seq>;<yyyy-mm-dd hh:mm:ss>;<LEVEL>;<SRC>;<code>;<text>
   ----------------------------------------------------------------------- *)
METHOD ExportLine : BOOL
VAR_INPUT
    (* Entry selector, 1 = newest *)
    iIdx : UINT;
END_VAR
VAR
    (* TRUE when the requested entry exists *)
    bOk  : BOOL;
    (* Level rendered as fixed-width ASCII tag *)
    sLvl : STRING(6);
    (* Line under construction (built right-to-left) *)
    sTmp : STRING(120);
END_VAR
    ExportLine := FALSE;
    bOk := THIS.GetEntry(iIdx);
    IF bOk THEN
        CASE out_stEntry.eLevel OF
            ET_SP_LogLevel#Debug: sLvl := 'DEBUG';
            ET_SP_LogLevel#Info:  sLvl := 'INFO ';
            ET_SP_LogLevel#Warn:  sLvl := 'WARN ';
            ELSE                  sLvl := 'ERROR';
        END_CASE

        sTmp := FUN_SP_UiToStr(UDINT_TO_UINT(out_stEntry.udiSeq MOD UDINT#100000));
        sTmp := CONCAT(sTmp, ';');
        sTmp := CONCAT(sTmp, FUN_SP_RtcToStr(out_stEntry.stTime));
        sTmp := CONCAT(sTmp, ';');
        sTmp := CONCAT(sTmp, sLvl);
        sTmp := CONCAT(sTmp, ';');
        sTmp := CONCAT(sTmp, FUN_SP_SrcText(out_stEntry.eSrc));
        sTmp := CONCAT(sTmp, ';');
        sTmp := CONCAT(sTmp, FUN_SP_UiToStr(out_stEntry.uiCode));
        sTmp := CONCAT(sTmp, ';');
        sTmp := CONCAT(sTmp, out_stEntry.sText);

        out_stEntry.sText := sTmp;
        ExportLine := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Clear (parent SP_Logger)
   Drop all stored entries.
   ----------------------------------------------------------------------- *)
METHOD Clear : UINT
    Clear := m_iCnt;                (* Number of dropped entries *)
    m_iHead := 1;
    m_iCnt  := 0;
    uiCount := 0;
END_METHOD
