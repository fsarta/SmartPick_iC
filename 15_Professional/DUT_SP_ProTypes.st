(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 15_Professional
   Worksheet : DUT - ST_SP_ProTypes
   -----------------------------------------------------------------------------
   Purpose   : Professional layer data model (roadmap R-16):

     - ST_SP_OeeView  : OEE snapshot mirrored to the HMI (availability,
                        performance, quality, OEE, time budget, MTBF/MTTR).
     - ST_SP_MaintCfg : Maintenance thresholds (grip cycles per robot,
                        camera shots, conveyor run minutes, pump minutes).
     - ST_SP_MaintStat: Maintenance counters and due flags (HMI mirror).
     - ST_SP_TestRes  : Startup self-test result record.

   All structures are plain data (no FB references) so they can be
   mirrored, logged or exported like any other cell state.
   =============================================================================
*)

TYPE ST_SP_OeeView :
STRUCT
    rAvail   : LREAL;       (* Availability = run time / planned time [0..1] *)
    rPerf    : LREAL;       (* Performance = ideal cycle x count / run time [0..1] *)
    rQual    : LREAL;       (* Quality = good picks / total picks [0..1] *)
    rOee     : LREAL;       (* OEE = A x P x Q [0..1] *)
    udiPlanMs: UDINT;       (* Planned (shift) time [ms] *)
    udiRunMs : UDINT;       (* Productive time [ms] *)
    udiDownMs: UDINT;       (* Downtime (fault) [ms] *)
    udiCycles: UDINT;       (* Cycles in the current shift *)
    udiGood  : UDINT;       (* Good picks in the current shift *)
    udiNg    : UDINT;       (* Failed picks in the current shift *)
    udiFaults: UDINT;       (* Fault events in the current shift *)
    rMtbfMin : LREAL;       (* Mean time between faults [min], EMA smoothed *)
    rMttrMin : LREAL;       (* Mean time to repair [min], EMA smoothed *)
END_STRUCT
END_TYPE

TYPE ST_SP_MaintCfg :
STRUCT
    (* Grip-cycle thresholds per robot (0 = counter disabled) 1..GC_ROBOTS *)
    audiRobCycles : ARRAY[1..4] OF UDINT;
    (* Camera shot thresholds (0 = disabled) 1..GC_CAMS *)
    audiCamShots  : ARRAY[1..2] OF UDINT;
    (* Conveyor run-time thresholds [min] (0 = disabled) 1..GC_FEEDS *)
    audiConvMin   : ARRAY[1..8] OF UDINT;
    (* Vacuum pump run-time threshold [min] (0 = disabled) *)
    udiPumpMin    : UDINT;
END_STRUCT
END_TYPE

TYPE ST_SP_MaintStat :
STRUCT
    (* Grip-cycle counters per robot 1..GC_ROBOTS *)
    audiRobCycles : ARRAY[1..4] OF UDINT;
    audiRobPct    : ARRAY[1..4] OF LREAL;   (* Load 0..1 *)
    abRobDue      : ARRAY[1..4] OF BOOL;    (* Maintenance due *)
    (* Camera shot counters 1..GC_CAMS *)
    audiCamShots  : ARRAY[1..2] OF UDINT;
    audiCamPct    : ARRAY[1..2] OF LREAL;
    abCamDue      : ARRAY[1..2] OF BOOL;
    (* Conveyor run-time counters [min] 1..GC_FEEDS *)
    audiConvMin   : ARRAY[1..8] OF UDINT;
    audiConvPct   : ARRAY[1..8] OF LREAL;
    abConvDue     : ARRAY[1..8] OF BOOL;
    (* Vacuum pump run-time counter [min] *)
    udiPumpMin    : UDINT;
    rPumpPct      : LREAL;
    bPumpDue      : BOOL;
    (* Aggregate *)
    bAnyDue       : BOOL;       (* TRUE when at least one threshold is reached *)
END_STRUCT
END_TYPE

TYPE ST_SP_TestRes :
STRUCT
    bPass    : BOOL;        (* TRUE = all checks passed *)
    uiChecks : UINT;        (* Number of checks executed *)
    uiFails  : UINT;        (* Number of failed checks *)
    (* Ids of the failed checks (0 = unused slot) *)
    auiFail  : ARRAY[1..16] OF UINT;
    (* Message of the first failure (English, operator facing) *)
    sMsg     : STRING(80);
    stRun    : Yt_YA_RTC_Struct; (* Wall clock of the last run (v1.8.0) *)
END_STRUCT
END_TYPE
