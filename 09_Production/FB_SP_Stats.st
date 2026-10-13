(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 09_Production
   Worksheet : FB - SP_Stats
   -----------------------------------------------------------------------------
   Purpose   : Production statistics: system counters, per-feed and
               per-type pick/place figures, cycle rate estimate and
               uptime (MotoPick 4 "comprehensive logging" support).
   =============================================================================
*)

FUNCTION_BLOCK SP_Stats
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    uiDtMs : UDINT;             (* Task period [ms] *)
    bProd  : BOOL;              (* TRUE while producing (uptime accrual) *)
END_VAR
VAR_OUTPUT
    stTot  : ST_SP_Counters;    (* System totals *)
    out_stCnt : ST_SP_Counters; (* Result buffer of GetFeed *)
    udiUptimeMs : UDINT;        (* Production uptime [ms] *)
    rPiecesPerH : LREAL;        (* Estimated pieces/hour (rolling) *)
END_VAR
VAR
    (* Per-feed counters (optional feed tag) 1..GC_FEEDS *)
    m_astFeed : ARRAY[1..8] OF ST_SP_Counters;
    m_udiWinMs : UDINT := 0;    (* Rate window accumulator *)
    m_udiWinPcs: UDINT := 0;    (* Pieces in window *)
    m_udiWinCnt: UDINT := 0;    (* Window counter for averaging *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF bProd THEN
    udiUptimeMs := udiUptimeMs + uiDtMs;
    m_udiWinMs  := m_udiWinMs + uiDtMs;

    IF m_udiWinMs >= GC_RATE_WIN THEN
        (* Pieces per hour over the last window *)
        rPiecesPerH := UDINT_TO_LREAL(m_udiWinPcs) * 3600000.0
                       / UDINT_TO_LREAL(m_udiWinMs);
        m_udiWinMs := UDINT#0;
        m_udiWinPcs := UDINT#0;
        m_udiWinCnt := m_udiWinCnt + 1;
    END_IF
END_IF
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: AddPick (parent SP_Stats)
   Register one pick result.
   ----------------------------------------------------------------------- *)
METHOD AddPick : BOOL
VAR_INPUT
    (* TRUE = successful place (else counted as fail) *)
    bOk   : BOOL;
    iFeed : SINT;               (* 0 = system totals only *)
END_VAR
VAR
    (* Clamped feed index (0 = totals only) *)
    iF : SINT;
END_VAR
    AddPick := TRUE;                (* Counter updated *)
    IF bOk THEN
        stTot.udiPickOk := stTot.udiPickOk + UDINT#1;
        m_udiWinPcs := m_udiWinPcs + UDINT#1;
    ELSE
        stTot.udiPickNg := stTot.udiPickNg + UDINT#1;
    END_IF
    IF (iFeed >= 1) AND (iFeed <= GC_FEEDS) THEN
        iF := iFeed;
        IF bOk THEN
            m_astFeed[iF].udiPickOk := m_astFeed[iF].udiPickOk + UDINT#1;
        ELSE
            m_astFeed[iF].udiPickNg := m_astFeed[iF].udiPickNg + UDINT#1;
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddPlace (parent SP_Stats)
   Register one place result.
   ----------------------------------------------------------------------- *)
METHOD AddPlace : BOOL
VAR_INPUT
    (* TRUE = successful place (else counted as fail) *)
    bOk   : BOOL;
    (* Feed whose counters are copied out *)
    iFeed : SINT;
END_VAR
VAR
    (* Clamped feed index (0 = totals only) *)
    iF : SINT;
END_VAR
    AddPlace := TRUE;               (* Counter updated *)
    IF bOk THEN
        stTot.udiPlaceOk := stTot.udiPlaceOk + UDINT#1;
    ELSE
        stTot.udiPlaceNg := stTot.udiPlaceNg + UDINT#1;
    END_IF
    IF (iFeed >= 1) AND (iFeed <= GC_FEEDS) THEN
        iF := iFeed;
        IF bOk THEN
            m_astFeed[iF].udiPlaceOk := m_astFeed[iF].udiPlaceOk + UDINT#1;
        ELSE
            m_astFeed[iF].udiPlaceNg := m_astFeed[iF].udiPlaceNg + UDINT#1;
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddCycle / AddAlarm (parent SP_Stats)
   Cycle and alarm counters.
   ----------------------------------------------------------------------- *)
METHOD AddCycle : BOOL
    AddCycle := TRUE;               (* Counter updated *)
    stTot.udiCycles := stTot.udiCycles + UDINT#1;
END_METHOD

METHOD AddAlarm : BOOL
    AddAlarm := TRUE;               (* Counter updated *)
    stTot.udiAlarms := stTot.udiAlarms + UDINT#1;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetFeed (parent SP_Stats)
   Copy the per-feed counters into out_stCnt. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD GetFeed : BOOL
VAR_INPUT
    (* Feed whose counters are copied out *)
    iFeed : SINT;
END_VAR
    GetFeed := FALSE;
    IF (iFeed >= 1) AND (iFeed <= GC_FEEDS) THEN
        out_stCnt := m_astFeed[iFeed];
        GetFeed := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Reset (parent SP_Stats)
   Clear all counters (production reset).
   ----------------------------------------------------------------------- *)
METHOD Reset : BOOL
VAR
    (* Feed loop index (counter reset) *)
    i : SINT;
END_VAR
    Reset := TRUE;                  (* Counters cleared *)
    stTot.udiPickOk := UDINT#0;
    stTot.udiPickNg := UDINT#0;
    stTot.udiPlaceOk := UDINT#0;
    stTot.udiPlaceNg := UDINT#0;
    stTot.udiCycles := UDINT#0;
    FOR i := 1 TO GC_FEEDS DO
        m_astFeed[i].udiPickOk := UDINT#0;
        m_astFeed[i].udiPickNg := UDINT#0;
        m_astFeed[i].udiPlaceOk := UDINT#0;
        m_astFeed[i].udiPlaceNg := UDINT#0;
    END_FOR
    udiUptimeMs := UDINT#0;
    rPiecesPerH := 0.0;
END_METHOD
