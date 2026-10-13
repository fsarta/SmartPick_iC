(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Rtc
   -----------------------------------------------------------------------------
   Purpose   : System time services (v1.8.0). Replaces the IEC "DT" type,
               which the iCube Engineer declaration editor does not offer
               on this target, with the official Yaskawa toolbox binding:

                 Y_YA_RealTimeClock  (FB, Y_Yaskawa_Toolbox library)
                   Enable : BOOL
                   Valid / Error : BOOL, ErrorID : UINT
                   Clock : Yt_YA_RTC_Struct  (Year/Month/Day/Hour/Minute/
                                               Second/mSec, all INT)
                   RTCString : STRING

   TIME MODEL (two independent sources, never mixed):
     - WALL CLOCK   g_stRtcNow  : real date/time for log entries, alarm
       raise/clear stamps, self-test run stamp and HMI display. Written
       ONLY by PRG_SP_TaskSvc (section 1). In simulation (g_bSim) or on
       RTC failure it is derived from the monotonic tick so the whole
       pipeline stays deterministic offline.
     - MONOTONIC TICK g_udiTickMs : free-running millisecond counter
       advanced by PRG_SP_TaskFast every cycle (+g_uiDtMs). The ONLY
       legal time base for durations (socket timeouts, camera trigger
       intervals, response timeouts): it never jumps, so NTP/DST wall
       clock adjustments cannot distort a supervision window. Wrap-safe
       by unsigned subtraction (correct for any elapsed << 49.7 days).

   Concurrency contract (same pattern as GVL_SP_Sync, single writer):
     g_FBRTC, g_stRtcNow, g_bRtcValid, g_uiRtcErr, g_sRtcNow
         -> written only by PRG_SP_TaskSvc, read anywhere (cosmetic tear
            acceptable: timestamps are information, never control data)
     g_udiTickMs
         -> written only by PRG_SP_TaskFast, read anywhere (UDINT writes
            are atomic on the 32-bit target)

   LIBRARY DEPENDENCY (CONFIRM on site): add the "Y_Yaskawa_Toolbox"
   library to the iCube project references (Library manager). The exact
   library revision must match the one installed on the controller.
   =============================================================================
*)

VAR
    (* ---- Wall clock (Y_Yaskawa_Toolbox binding) ----------------------- *)
    (* Vendor RTC FB instance; called ONLY by PRG_SP_TaskSvc section 1 *)
    g_FBRTC     : Y_YA_RealTimeClock;
    (* Latest wall-clock snapshot (Year/Month/Day/Hour/Minute/Second/mSec) *)
    g_stRtcNow  : Yt_YA_RTC_Struct;
    (* TRUE when the vendor RTC returned a Valid clock this cycle *)
    g_bRtcValid : BOOL := FALSE;
    (* Last RTC FB error id (0 = none; diagnostics mirror) *)
    g_uiRtcErr  : UINT := UINT#0;
    (* Formatted snapshot 'YYYY-MM-DD HH:MM:SS.mmm' (HMI / diagnostics) *)
    g_sRtcNow   : STRING(23);

    (* ---- Monotonic tick (duration time base) -------------------------- *)
    (* Milliseconds since boot, advanced by PRG_SP_TaskFast (+g_uiDtMs);
       free-running: elapsed times use unsigned subtraction *)
    g_udiTickMs : UDINT := UDINT#0;
END_VAR
