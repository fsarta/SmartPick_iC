(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION - FUN_SP_TickToRtc
   -----------------------------------------------------------------------------
   Purpose   : Convert the monotonic millisecond tick (GVL_SP_Rtc.
               g_udiTickMs) into a Yt_YA_RTC_Struct wall-clock record.
               Used by PRG_SP_TaskSvc when the vendor RTC is not valid:
               in simulation (g_bSim = TRUE, deterministic timestamps for
               reproducible tests) and as fallback on RTC hardware errors.
               The conversion bases the day count on the civil calendar
               epoch 1970-01-01 (Howard Hinnant algorithm, same domain as
               the legacy DT formatter this function replaces in v1.8.0).
   -----------------------------------------------------------------------------
   Notes     : - The tick is free-running UDINT: after ~49.7 days it wraps
                 and simulated dates restart (cosmetic only, never control
                 data). Timeouts are unaffected (unsigned subtraction).
               - VAR / VAR_INPUT only, no pointers, no recursion.
   =============================================================================
*)

FUNCTION FUN_SP_TickToRtc : Yt_YA_RTC_Struct
VAR_INPUT
    (* Monotonic milliseconds since boot (GVL_SP_Rtc.g_udiTickMs) *)
    udiMs : UDINT;
END_VAR
VAR
    (* Whole seconds since epoch (working copy) *)
    udiSec : UDINT;
    (* Days since epoch *)
    udiDay : UDINT;
    (* Seconds of the current day *)
    udiT   : UDINT;
    (* Days since epoch (Howard Hinnant civil-calendar algorithm) *)
    diZ    : DINT;
    (* 400-year era index of diZ *)
    diEra  : DINT;
    (* Day of era (0..146096) *)
    diDoe  : DINT;
    (* Year of era (0..399) *)
    diYoe  : DINT;
    (* Absolute year (calendar) *)
    diY    : DINT;
    (* Day of year (0..365) *)
    diDoy  : DINT;
    (* Month index in the shifted 5-month-per-year mapping *)
    diMp   : DINT;
    (* Month (1..12) *)
    diM    : DINT;
    (* Day of month (1..31) *)
    diD    : DINT;
END_VAR
    udiSec := udiMs / UDINT#1000;
    udiDay := udiSec / UDINT#86400;
    udiT   := udiSec MOD UDINT#86400;

    FUN_SP_TickToRtc.Hour   := DINT_TO_INT(UDINT_TO_DINT(udiT / UDINT#3600));
    FUN_SP_TickToRtc.Minute := DINT_TO_INT(UDINT_TO_DINT((udiT MOD UDINT#3600) / UDINT#60));
    FUN_SP_TickToRtc.Second := DINT_TO_INT(UDINT_TO_DINT(udiT MOD UDINT#60));
    FUN_SP_TickToRtc.mSec   := DINT_TO_INT(UDINT_TO_DINT(udiMs MOD UDINT#1000));

    (* civil_from_days (Hinnant), positive era domain *)
    diZ   := UDINT_TO_DINT(udiDay) + 719468;
    diEra := diZ / 146097;
    diDoe := diZ - diEra * 146097;                                    (* [0, 146096] *)
    diYoe := (diDoe - diDoe/1460 + diDoe/36524 - diDoe/146096) / 365; (* [0, 399]   *)
    diY   := diYoe + diEra * 400;
    diDoy := diDoe - (365*diYoe + diYoe/4 - diYoe/100);               (* [0, 365]   *)
    diMp  := (5*diDoy + 2)/153;                                       (* [0, 11]    *)
    diD   := diDoy - (153*diMp + 2)/5 + 1;                            (* [1, 31]    *)
    diM   := diMp + 3;
    IF diMp >= 10 THEN
        diM := diMp - 9;
    END_IF
    IF diM <= 2 THEN
        diY := diY + 1;
    END_IF

    FUN_SP_TickToRtc.Year  := DINT_TO_INT(diY);
    FUN_SP_TickToRtc.Month := DINT_TO_INT(diM);
    FUN_SP_TickToRtc.Day   := DINT_TO_INT(diD);
END_FUNCTION
