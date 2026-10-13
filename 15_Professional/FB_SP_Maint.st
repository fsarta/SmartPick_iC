(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 15_Professional
   Worksheet : FB - SP_Maint
   -----------------------------------------------------------------------------
   Purpose   : Predictive maintenance counters (roadmap R-16). Tracks the
               wear-relevant volumes of the cell and flags maintenance
               due states before failures happen:

     - Grip cycles per robot (from the lifetime pick counters of the
       robot status mirrors, delta-scanned by this FB)
     - Camera shots (from the camera HMI mirrors, delta-scanned)
     - Conveyor run time in minutes (from the enable vector mirror)
     - Vacuum pump run time in minutes (bPumpOn input)

   Each item has a configurable threshold (ST_SP_MaintCfg, 0 = disabled);
   the load percentage and the due flag are published for the HMI and a
   cell alarm can be raised by Main (bAnyDue rising edge).

   Delta scanning: the FB keeps previous-cycle mirrors internally, so the
   wiring is a single body call plus the threshold configuration.

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_Maint
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    uiDtMs  : UDINT;            (* Task period [ms] *)
    bPumpOn : BOOL;             (* Vacuum pump running *)
    (* Configuration: thresholds (0 = counter disabled). Main/HMI write. *)
    stCfg   : ST_SP_MaintCfg;
    (* Live mirrors written by Main before this call (same cycle) *)
    audiRobPicks : ARRAY[1..GC_ROBOTS] OF UDINT;    (* Lifetime picks per robot *)
    audiCamTrig  : ARRAY[1..GC_CAMS] OF UDINT;      (* Lifetime triggers per camera *)
    abConvRun    : ARRAY[1..GC_FEEDS] OF BOOL;      (* Conveyor running *)
END_VAR
VAR_OUTPUT
    (* Published maintenance state (mirrored to the HMI by Main) *)
    stStat : ST_SP_MaintStat;
END_VAR
VAR
    (* Previous-cycle mirror scans (delta sources) *)
    m_audiRobPrev : ARRAY[1..GC_ROBOTS] OF UDINT;
m_audiCamPrev : ARRAY[1..GC_CAMS] OF UDINT; (* Prev-cycle shot counters (delta scan for maintenance) *)
    (* Conveyor minute accumulator (ms -> minutes) *)
    m_audiConvMs  : ARRAY[1..GC_FEEDS] OF UDINT;
    (* Pump minute accumulator (ms -> minutes) *)
    m_udiPumpMs   : UDINT := 0;
    (* Fill-if-empty guard: thresholds applied once *)
    m_bCfgDef : BOOL := FALSE;
    (* Loop indices *)
    i : SINT;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* 0) Default thresholds on the first call (fill-if-empty) ----------------- *)
IF NOT m_bCfgDef THEN
    m_bCfgDef := TRUE;
    IF stCfg.udiPumpMin = UDINT#0 THEN
        stCfg.udiPumpMin := UDINT#20000;        (* ~333 h service window *)
    END_IF
    FOR i := 1 TO GC_ROBOTS DO
        IF stCfg.audiRobCycles[i] = UDINT#0 THEN
            stCfg.audiRobCycles[i] := UDINT#1000000;    (* Grip service count *)
        END_IF
    END_FOR
    FOR i := 1 TO GC_CAMS DO
        IF stCfg.audiCamShots[i] = UDINT#0 THEN
            stCfg.audiCamShots[i] := UDINT#5000000;     (* Illumination life *)
        END_IF
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        IF stCfg.audiConvMin[i] = UDINT#0 THEN
            stCfg.audiConvMin[i] := UDINT#100000;       (* Belt service time *)
        END_IF
    END_FOR
END_IF

(* 1) Grip cycles per robot (delta of the lifetime pick counters) ---------- *)
stStat.bAnyDue := FALSE;
FOR i := 1 TO GC_ROBOTS DO
    IF audiRobPicks[i] > m_audiRobPrev[i] THEN
        stStat.audiRobCycles[i] := stStat.audiRobCycles[i]
                                   + (audiRobPicks[i] - m_audiRobPrev[i]);
    END_IF
    m_audiRobPrev[i] := audiRobPicks[i];
    IF stCfg.audiRobCycles[i] > UDINT#0 THEN
        stStat.audiRobPct[i] := UDINT_TO_LREAL(stStat.audiRobCycles[i])
                                / UDINT_TO_LREAL(stCfg.audiRobCycles[i]);
        stStat.abRobDue[i] := (stStat.audiRobPct[i] >= 1.0);
        IF stStat.abRobDue[i] THEN stStat.bAnyDue := TRUE; END_IF
    ELSE
        stStat.audiRobPct[i] := 0.0;
        stStat.abRobDue[i] := FALSE;
    END_IF
END_FOR

(* 2) Camera shots (delta of the trigger counters) -------------------------- *)
FOR i := 1 TO GC_CAMS DO
    IF audiCamTrig[i] > m_audiCamPrev[i] THEN
        stStat.audiCamShots[i] := stStat.audiCamShots[i]
                                  + (audiCamTrig[i] - m_audiCamPrev[i]);
    END_IF
    m_audiCamPrev[i] := audiCamTrig[i];
    IF stCfg.audiCamShots[i] > UDINT#0 THEN
        stStat.audiCamPct[i] := UDINT_TO_LREAL(stStat.audiCamShots[i])
                                / UDINT_TO_LREAL(stCfg.audiCamShots[i]);
        stStat.abCamDue[i] := (stStat.audiCamPct[i] >= 1.0);
        IF stStat.abCamDue[i] THEN stStat.bAnyDue := TRUE; END_IF
    ELSE
        stStat.audiCamPct[i] := 0.0;
        stStat.abCamDue[i] := FALSE;
    END_IF
END_FOR

(* 3) Conveyor run time (minutes) -------------------------------------------- *)
FOR i := 1 TO GC_FEEDS DO
    IF abConvRun[i] THEN
        m_audiConvMs[i] := m_audiConvMs[i] + uiDtMs;
        IF m_audiConvMs[i] >= UDINT#60000 THEN
            m_audiConvMs[i] := m_audiConvMs[i] - UDINT#60000;
            stStat.audiConvMin[i] := stStat.audiConvMin[i] + UDINT#1;
        END_IF
    END_IF
    IF stCfg.audiConvMin[i] > UDINT#0 THEN
        stStat.audiConvPct[i] := UDINT_TO_LREAL(stStat.audiConvMin[i])
                                 / UDINT_TO_LREAL(stCfg.audiConvMin[i]);
        stStat.abConvDue[i] := (stStat.audiConvPct[i] >= 1.0);
        IF stStat.abConvDue[i] THEN stStat.bAnyDue := TRUE; END_IF
    ELSE
        stStat.audiConvPct[i] := 0.0;
        stStat.abConvDue[i] := FALSE;
    END_IF
END_FOR

(* 4) Vacuum pump run time (minutes) ------------------------------------------- *)
IF bPumpOn THEN
    m_udiPumpMs := m_udiPumpMs + uiDtMs;
    IF m_udiPumpMs >= UDINT#60000 THEN
        m_udiPumpMs := m_udiPumpMs - UDINT#60000;
        stStat.udiPumpMin := stStat.udiPumpMin + UDINT#1;
    END_IF
END_IF
IF stCfg.udiPumpMin > UDINT#0 THEN
    stStat.rPumpPct := UDINT_TO_LREAL(stStat.udiPumpMin)
                       / UDINT_TO_LREAL(stCfg.udiPumpMin);
    stStat.bPumpDue := (stStat.rPumpPct >= 1.0);
    IF stStat.bPumpDue THEN stStat.bAnyDue := TRUE; END_IF
ELSE
    stStat.rPumpPct := 0.0;
    stStat.bPumpDue := FALSE;
END_IF
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: ResetAll (parent SP_Maint)
   Clear every counter (after the maintenance intervention).
   ----------------------------------------------------------------------- *)
METHOD ResetAll : BOOL
VAR
    (* Loop index over the counter families *)
    i : SINT;
END_VAR
    ResetAll := TRUE;               (* Counters cleared *)
    FOR i := 1 TO GC_ROBOTS DO
        stStat.audiRobCycles[i] := UDINT#0;
        stStat.audiRobPct[i] := 0.0;
        stStat.abRobDue[i] := FALSE;
    END_FOR
    FOR i := 1 TO GC_CAMS DO
        stStat.audiCamShots[i] := UDINT#0;
        stStat.audiCamPct[i] := 0.0;
        stStat.abCamDue[i] := FALSE;
    END_FOR
    FOR i := 1 TO GC_FEEDS DO
        stStat.audiConvMin[i] := UDINT#0;
        stStat.audiConvPct[i] := 0.0;
        stStat.abConvDue[i] := FALSE;
    END_FOR
    stStat.udiPumpMin := UDINT#0;
    stStat.rPumpPct := 0.0;
    stStat.bPumpDue := FALSE;
    stStat.bAnyDue := FALSE;
END_METHOD
