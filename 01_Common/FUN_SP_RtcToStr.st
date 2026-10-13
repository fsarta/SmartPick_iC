(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION - FUN_SP_RtcToStr
   -----------------------------------------------------------------------------
   Purpose   : Format a Yt_YA_RTC_Struct (Yaskawa toolbox real-time clock,
               v1.8.0 - replaces the IEC DT based FUN_SP_DtToStr) as
               'YYYY-MM-DD HH:MM:SS.mmm'. The nil timestamp (GC_stRtcNil,
               all fields zero) formats as '0000-00-00 00:00:00.000' so
               alarm "not cleared" records stay visually explicit.
   -----------------------------------------------------------------------------
   Constraints: VAR / VAR_INPUT only, no pointers, no recursion.
   =============================================================================
*)

FUNCTION FUN_SP_RtcToStr : STRING(23)
VAR_INPUT
    (* RTC snapshot to format (Yaskawa Yt_YA_RTC_Struct, INT fields) *)
    stRtc : Yt_YA_RTC_Struct;
END_VAR
VAR
    (* Date part yyyy-mm-dd *)
    sY   : STRING(10);
    (* Time part hh:mm:ss.mmm *)
    sT   : STRING(12);
    (* Field working copy (0-based INT fields are clamped for formatting) *)
    iV   : DINT;
END_VAR
    (* ---- Date part: YYYY-MM-DD ---------------------------------------- *)
    iV  := DINT#0;
    IF stRtc.Year > 0 THEN
        iV := INT_TO_DINT(stRtc.Year);
    END_IF
    sY := FUN_SP_DigCh(iV / 1000 MOD 10);
    sY := CONCAT(sY, FUN_SP_DigCh(iV / 100 MOD 10));
    sY := CONCAT(sY, FUN_SP_DigCh(iV / 10 MOD 10));
    sY := CONCAT(sY, FUN_SP_DigCh(iV MOD 10));
    sY := CONCAT(sY, '-');

    iV := INT_TO_DINT(stRtc.Month);
    IF (iV < 0) OR (iV > 9) THEN
        iV := 0;                    (* Nil / invalid -> 00 *)
    END_IF
    sY := CONCAT(sY, FUN_SP_DigCh(iV / 10));
    sY := CONCAT(sY, FUN_SP_DigCh(iV MOD 10));
    sY := CONCAT(sY, '-');

    iV := INT_TO_DINT(stRtc.Day);
    IF (iV < 0) OR (iV > 31) THEN
        iV := 0;
    END_IF
    sY := CONCAT(sY, FUN_SP_DigCh(iV / 10));
    sY := CONCAT(sY, FUN_SP_DigCh(iV MOD 10));

    (* ---- Time part: HH:MM:SS.mmm --------------------------------------- *)
    iV := INT_TO_DINT(stRtc.Hour);
    IF (iV < 0) OR (iV > 23) THEN
        iV := 0;
    END_IF
    sT := FUN_SP_DigCh(iV / 10);
    sT := CONCAT(sT, FUN_SP_DigCh(iV MOD 10));
    sT := CONCAT(sT, ':');

    iV := INT_TO_DINT(stRtc.Minute);
    IF (iV < 0) OR (iV > 59) THEN
        iV := 0;
    END_IF
    sT := CONCAT(sT, FUN_SP_DigCh(iV / 10));
    sT := CONCAT(sT, FUN_SP_DigCh(iV MOD 10));
    sT := CONCAT(sT, ':');

    iV := INT_TO_DINT(stRtc.Second);
    IF (iV < 0) OR (iV > 59) THEN
        iV := 0;
    END_IF
    sT := CONCAT(sT, FUN_SP_DigCh(iV / 10));
    sT := CONCAT(sT, FUN_SP_DigCh(iV MOD 10));
    sT := CONCAT(sT, '.');

    iV := INT_TO_DINT(stRtc.mSec);
    IF (iV < 0) OR (iV > 999) THEN
        iV := 0;
    END_IF
    sT := CONCAT(sT, FUN_SP_DigCh(iV / 100));
    sT := CONCAT(sT, FUN_SP_DigCh(iV / 10 MOD 10));
    sT := CONCAT(sT, FUN_SP_DigCh(iV MOD 10));

    FUN_SP_RtcToStr := CONCAT(sY, sT);
END_FUNCTION
