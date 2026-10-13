(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION - FUN_SP_DtToStr
   -----------------------------------------------------------------------------
   Purpose   : Format a DT value as 'YYYY-MM-DD HH:MM:SS' (ISO-like, UTC of
               the supplied DT). Self-contained civil-calendar conversion,
               no vendor-specific time functions required.
   -----------------------------------------------------------------------------
   Constraints: VAR / VAR_INPUT only, no pointers, no recursion.
   =============================================================================
*)

FUNCTION FUN_SP_DtToStr : STRING(19)
VAR_INPUT
    dtVal : DT;      (* Seconds since 1970-01-01 00:00:00 *)
END_VAR
VAR
    (* Total seconds since epoch (working copy) *)
    udiSec : UDINT;
    udiDay : UDINT;  (* Days since epoch *)
    udiT   : UDINT;
    (* Hour of day (00..23) *)
    uiHH   : UINT;
    (* Minute of hour (00..59) *)
    uiMM   : UINT;
    (* Second of minute (00..59) *)
    uiSS   : UINT;
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
    (* Formatted date part yyyy-mm-dd *)
    sY     : STRING(10);
    (* Formatted time part hh:mm:ss *)
    sT     : STRING(8);
END_VAR
    udiSec := DT_TO_UDINT(dtVal);
    udiDay := udiSec / UDINT#86400;
    udiT   := udiSec MOD UDINT#86400;

    uiHH := UDINT_TO_UINT(udiT / UDINT#3600);
    uiMM := UDINT_TO_UINT((udiT MOD UDINT#3600) / UDINT#60);
    uiSS := UDINT_TO_UINT(udiT MOD UDINT#60);

    (* civil_from_days (Hinnant), positive era domain is sufficient for DT *)
    diZ   := UDINT_TO_DINT(udiDay) + 719468;
    diEra := diZ / 146097;
    diDoe := diZ - diEra * 146097;                                  (* [0, 146096] *)
    diYoe := (diDoe - diDoe/1460 + diDoe/36524 - diDoe/146096) / 365; (* [0, 399]  *)
    diY   := diYoe + diEra * 400;
    diDoy := diDoe - (365*diYoe + diYoe/4 - diYoe/100);             (* [0, 365]  *)
    diMp  := (5*diDoy + 2)/153;                                     (* [0, 11]   *)
    diD   := diDoy - (153*diMp + 2)/5 + 1;                          (* [1, 31]   *)
    diM   := diMp + 3;
    IF diMp >= 10 THEN
        diM := diMp - 9;
    END_IF
    IF diM <= 2 THEN
        diY := diY + 1;
    END_IF

    (* Assemble date part: YYYY-MM-DD *)
    sY := FUN_SP_DigCh(diY / 1000 MOD 10);
    sY := CONCAT(sY, FUN_SP_DigCh(diY / 100 MOD 10));
    sY := CONCAT(sY, FUN_SP_DigCh(diY / 10 MOD 10));
    sY := CONCAT(sY, FUN_SP_DigCh(diY MOD 10));
    sY := CONCAT(sY, '-');
    sY := CONCAT(sY, FUN_SP_DigCh(diM / 10));
    sY := CONCAT(sY, FUN_SP_DigCh(diM MOD 10));
    sY := CONCAT(sY, '-');
    sY := CONCAT(sY, FUN_SP_DigCh(diD / 10));
    sY := CONCAT(sY, FUN_SP_DigCh(diD MOD 10));

    (* Assemble time part: HH:MM:SS *)
    sT := FUN_SP_DigCh(UINT_TO_DINT(uiHH / 10));
    sT := CONCAT(sT, FUN_SP_DigCh(UINT_TO_DINT(uiHH MOD 10)));
    sT := CONCAT(sT, ':');
    sT := CONCAT(sT, FUN_SP_DigCh(UINT_TO_DINT(uiMM / 10)));
    sT := CONCAT(sT, FUN_SP_DigCh(UINT_TO_DINT(uiMM MOD 10)));
    sT := CONCAT(sT, ':');
    sT := CONCAT(sT, FUN_SP_DigCh(UINT_TO_DINT(uiSS / 10)));
    sT := CONCAT(sT, FUN_SP_DigCh(UINT_TO_DINT(uiSS MOD 10)));

    FUN_SP_DtToStr := CONCAT(CONCAT(sY, ' '), sT);
END_FUNCTION
