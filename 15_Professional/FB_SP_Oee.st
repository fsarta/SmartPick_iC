(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 15_Professional
   Worksheet : FB - SP_Oee
   -----------------------------------------------------------------------------
   Purpose   : OEE / KPI engine (roadmap R-16). Computes the classic
               Overall Equipment Effectiveness over the current shift:

     Availability = productive time / planned time
     Performance  = (ideal cycle time x cycles) / productive time
     Quality      = good picks / (good + failed picks)
     OEE          = A x P x Q

   Plus maintenance-oriented reliability KPIs:
     - MTBF: mean time between fault events (EMA smoothed, alpha = 0.2)
     - MTTR: mean time to repair (fault duration, EMA smoothed)

   Time model: the shift clock accrues planned time while bShift is TRUE
   (gate it with the system running OR a physical shift input). Downtime
   accrues while bFault. Productive time = planned - downtime. Counters
   are read from the SP_Stats snapshot (stCnt) against the shift base
   (Reset), so shift changes need no access to internal FB state.

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_Oee
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    uiDtMs  : UDINT;            (* Task period [ms] *)
    bShift  : BOOL;             (* TRUE = shift running (planned time accrues) *)
    bFault  : BOOL;             (* TRUE = any robot/system fault active *)
    (* Statistics snapshot (SP_Stats totals, written by Main every cycle) *)
    stCnt   : ST_SP_Counters;
    (* Ideal cycle time per piece [ms] (performance reference) *)
    rIdealCycleMs : LREAL := 2000.0;
END_VAR
VAR_OUTPUT
    (* OEE snapshot (mirrored to the HMI by Main) *)
    stView : ST_SP_OeeView;
END_VAR
VAR
    (* Shift base counters (snapshot at Reset) *)
    m_stBase : ST_SP_Counters;
    (* Fault edge detection and timers *)
    m_bFaultPrev : BOOL;
    (* Current fault duration [ms] *)
    m_udiFaultT  : UDINT := 0;
    (* Productive time since the last fault recovery [ms] (MTBF sample) *)
    m_udiRunSince: UDINT := 0;
    (* TRUE after the first fault pair (EMA needs two samples) *)
    m_bMtValid : BOOL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* 1) Time budget ---------------------------------------------------------- *)
IF bShift THEN
    stView.udiPlanMs := stView.udiPlanMs + uiDtMs;
    IF bFault THEN
        stView.udiDownMs := stView.udiDownMs + uiDtMs;
        m_udiFaultT := m_udiFaultT + uiDtMs;
    ELSE
        m_udiRunSince := m_udiRunSince + uiDtMs;
    END_IF
END_IF

(* 2) Fault edges (MTBF / MTTR sampling) ------------------------------------ *)
IF bFault AND (NOT m_bFaultPrev) THEN
    (* Fault rising edge: event counted *)
    stView.udiFaults := stView.udiFaults + UDINT#1;
END_IF
IF (NOT bFault) AND m_bFaultPrev THEN
    (* Fault falling edge: sample MTTR (fault duration) and MTBF (run since) *)
    IF m_udiFaultT > UDINT#0 THEN
        IF m_bMtValid THEN
            stView.rMttrMin := stView.rMttrMin * 0.8
                + (UDINT_TO_LREAL(m_udiFaultT) / 60000.0) * 0.2;
            stView.rMtbfMin := stView.rMtbfMin * 0.8
                + (UDINT_TO_LREAL(m_udiRunSince) / 60000.0) * 0.2;
        ELSE
            stView.rMttrMin := UDINT_TO_LREAL(m_udiFaultT) / 60000.0;
            stView.rMtbfMin := UDINT_TO_LREAL(m_udiRunSince) / 60000.0;
            m_bMtValid := TRUE;
        END_IF
    END_IF
    m_udiFaultT := UDINT#0;
    m_udiRunSince := UDINT#0;
END_IF
m_bFaultPrev := bFault;

(* 3) Shift counters (delta against the base) ------------------------------- *)
stView.udiCycles := stCnt.udiCycles - m_stBase.udiCycles;
stView.udiGood   := stCnt.udiPickOk - m_stBase.udiPickOk;
stView.udiNg     := stCnt.udiPickNg - m_stBase.udiPickNg;

(* 4) Productive time and OEE factors ---------------------------------------- *)
IF stView.udiPlanMs > (stView.udiDownMs) THEN
    stView.udiRunMs := stView.udiPlanMs - stView.udiDownMs;
ELSE
    stView.udiRunMs := UDINT#0;
END_IF

(* Availability *)
IF stView.udiPlanMs >= UDINT#1000 THEN
    stView.rAvail := UDINT_TO_LREAL(stView.udiRunMs)
                     / UDINT_TO_LREAL(stView.udiPlanMs);
ELSE
    stView.rAvail := 0.0;       (* Not enough planned time sampled yet *)
END_IF

(* Performance *)
IF (stView.udiRunMs >= UDINT#1000) AND (rIdealCycleMs > 0.0) THEN
    stView.rPerf := (UDINT_TO_LREAL(stView.udiCycles) * rIdealCycleMs)
                    / UDINT_TO_LREAL(stView.udiRunMs);
ELSE
    stView.rPerf := 0.0;
END_IF

(* Quality *)
IF (stView.udiGood + stView.udiNg) >= UDINT#1 THEN
    stView.rQual := UDINT_TO_LREAL(stView.udiGood)
                    / UDINT_TO_LREAL(stView.udiGood + stView.udiNg);
ELSE
    stView.rQual := 0.0;
END_IF

(* Clamp to sane ranges and compose *)
IF stView.rAvail > 1.0 THEN stView.rAvail := 1.0; END_IF
IF stView.rPerf  > 1.0 THEN stView.rPerf  := 1.0; END_IF
IF stView.rQual  > 1.0 THEN stView.rQual  := 1.0; END_IF
stView.rOee := stView.rAvail * stView.rPerf * stView.rQual;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Reset (parent SP_Oee)
   Shift reset: clears the time budget, fault statistics and re-bases the
   counter deltas on the current totals snapshot.
   ----------------------------------------------------------------------- *)
METHOD Reset : BOOL
VAR_INPUT
    (* Current totals snapshot (new shift base) *)
    stCnt : ST_SP_Counters;
END_VAR
    Reset := TRUE;                  (* Shift view re-based *)
    stView.udiPlanMs := UDINT#0;
    stView.udiRunMs  := UDINT#0;
    stView.udiDownMs := UDINT#0;
    stView.udiCycles := UDINT#0;
    stView.udiGood   := UDINT#0;
    stView.udiNg     := UDINT#0;
    stView.udiFaults := UDINT#0;
    stView.rAvail := 0.0;
    stView.rPerf  := 0.0;
    stView.rQual  := 0.0;
    stView.rOee   := 0.0;
    (* MTBF/MTTR accumulators survive a shift reset on purpose (they are
       reliability figures, not shift figures); use MTReset for those. *)
    m_udiFaultT := UDINT#0;
    m_udiRunSince := UDINT#0;
    m_stBase := stCnt;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: MTReset (parent SP_Oee)
   Clear the MTBF/MTTR estimators (after a major overhaul).
   ----------------------------------------------------------------------- *)
METHOD MTReset : BOOL
    MTReset := TRUE;                (* MTBF/MTTR cleared *)
    stView.rMtbfMin := 0.0;
    stView.rMttrMin := 0.0;
    m_bMtValid := FALSE;
    m_udiFaultT := UDINT#0;
    m_udiRunSince := UDINT#0;
END_METHOD
