(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Io
   -----------------------------------------------------------------------------
   Purpose   : Physical I/O mirror of the application.

   (v1.8.0) The former single time source g_dtNow : DT lived here; the
   DT type is not offered by the iCube declaration editor on this target.
   Time services moved to GVL_SP_Rtc: wall clock from Y_YA_RealTimeClock
   (Y_Yaskawa_Toolbox) + monotonic millisecond tick g_udiTickMs.

   I/O binding: the arrays below are the ONLY places where application
   code touches tool signals. Map each element to the physical terminals
   (%I / %Q) in the iCube hardware view, or feed them from the fieldbus
   process image. Channel mapping convention (automatic mode):
     tool channel = (robot - 1) * GC_TOOLS + tool      (1..16)
   Analog conveyor speeds: map grConvDrive[i] to a %QW scaled 0.0..1.0.
   =============================================================================
*)

VAR
    (* Safety chain *)
    bEStopOk : BOOL := TRUE;    (* Emergency stop chain healthy *)
    bSafetyOk: BOOL := TRUE;    (* Guards / scanners healthy *)

    (* Tool signals: PICK (out), PLACE (out), FEEDBACK (in) - MotoPick 4 spec 1..GC_ROBOTS*GC_TOOLS *)
    abPickOut    : ARRAY[1..16] OF BOOL;
    (* Place/grip digital outputs (robot x tool channel map) 1..GC_ROBOTS*GC_TOOLS *)
    abPlaceOut   : ARRAY[1..16] OF BOOL;
    (* Grip feedback inputs (looped back in simulation) 1..GC_ROBOTS*GC_TOOLS *)
    abToolFbkIn  : ARRAY[1..16] OF BOOL;

    (* Conveyor drive: analog speed factor per feed (0.0 .. 1.0) 1..GC_FEEDS *)
    grConvDrive  : ARRAY[1..8] OF REAL;

    (* Tray / light barrier sensors per outfeed 1..GC_FEEDS *)
    abTraySensor : ARRAY[1..8] OF BOOL;
END_VAR
