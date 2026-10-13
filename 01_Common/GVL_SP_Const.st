(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : GVL - GVL_SP_Const
   -----------------------------------------------------------------------------
   Purpose   : Compile-time system limits and physical constants.
               Sized for the reduced iC 9226M-EC configuration; raise the
               constants to scale the system (memory permitting).
   -----------------------------------------------------------------------------
   UNITS CONVENTION (v1.7.0):
     - ALL distances  : millimetres  [mm]  (positions, speeds [mm/s], offsets)
     - ALL rotations  : degrees      [deg] (yaw/roll/rot steps, stored and
       exchanged in deg everywhere; SIN/COS/ATAN receive an explicit
       GC_DEG2RAD conversion at the call site and results are mapped back
       with GC_RAD2DEG - see FUN_SP_Atan2 / FUN_SP_NormAng in FUN_SP_Utils).
   -----------------------------------------------------------------------------
   Notes     : - Constants are declared here (GVL VAR CONSTANT) and NOT in a
                 data type worksheet, so they are usable from every worksheet.
                 This respects the iCube rule "constants declared in a DDT
                 are only usable within that DDT".
               - Array declarations everywhere reference these constants.
   =============================================================================
*)

VAR CONSTANT
    (* ------------------- System scale (compile-time limits) -------------- *)
    GC_SP_VER_MAJOR : UINT := 1;        (* SmartPick_iC major version *)
    GC_SP_VER_MINOR : UINT := 8;        (* SmartPick_iC minor version *)
    GC_SP_VER_BUILD : UINT := 0;        (* SmartPick_iC build number *)

    GC_ROBOTS   : SINT  := 4;           (* Max robots / kinematic groups *)
    GC_FEEDS    : SINT  := 8;           (* Max feeds (tracked conveyors) *)
    GC_CAMS     : SINT  := 2;           (* Max cameras *)
    GC_TOOLS    : SINT  := 4;           (* Max tools per robot *)
    GC_TYPES    : SINT  := 32;          (* Max product types *)
    GC_CUPS     : SINT  := 4;           (* Max cups/tool => parts per cycle *)
    GC_SEQ      : SINT  := 8;           (* Max type mix entries per batch *)
    GC_QUEUE    : SINT  := 64;          (* Max tracked items per feed *)
    GC_LAYERS   : SINT  := 4;           (* Max tray layers per pattern *)
    GC_PATT     : SINT  := 8;           (* Max place patterns *)
    GC_PATT_SLOTS : SINT := 16;         (* Max slots per pattern (rows x cols) *)
    GC_BATCHES  : SINT  := 8;           (* Max batch definitions *)
    GC_LOG_N    : SINT  := 256;         (* Logger ring buffer depth *)
    GC_ALARM_N  : SINT  := 64;          (* Alarm registry depth *)
    GC_MOVAVG_N : SINT  := 8;           (* Speed filter taps *)
    GC_STRCFG   : SINT  := 128;         (* Generic config string length *)
    GC_STRMSG   : SINT  := 120;         (* Message string length *)
    GC_ZONES    : SINT  := 4;           (* Max interlock zones (R-05 zone guard) *)
    GC_ZONE_NONE: SINT  := 0;           (* Zone id "unguarded" *)

    (* ------------------- Physical / mathematical constants --------------- *)
    (* Trig-boundary helpers: the application stores angles in DEGREES;
       GC_DEG2RAD / GC_RAD2DEG are applied ONLY at SIN/COS/ATAN call sites. *)
    GC_PI       : LREAL := 3.14159265358979323846;   (* pi [rad], trig use only *)
    GC_2PI      : LREAL := 6.28318530717958647692;   (* 2*pi [rad], trig use only *)
    GC_DEG2RAD  : LREAL := 0.01745329251994329577;   (* pi / 180 *)
    GC_RAD2DEG  : LREAL := 57.29577951308232087680;  (* 180 / pi *)
    GC_90       : LREAL := 90.0;                     (* Quarter turn [deg] *)
    GC_180      : LREAL := 180.0;                    (* Half turn [deg] *)
    GC_360      : LREAL := 360.0;                    (* Full turn [deg] *)

    (* ------------------- Timing / housekeeping --------------------------- *)
    (* Nil timestamp sentinel for the v1.8.0 RTC structs: an all-zero
       Yt_YA_RTC_Struct means "no timestamp" (e.g. alarm never cleared).
       The type comes from the Y_Yaskawa_Toolbox library (vendor RTC). *)
    GC_stRtcNil     : Yt_YA_RTC_Struct := (Year := 0, Month := 0, Day := 0,
                                           Hour := 0, Minute := 0, Second := 0,
                                           mSec := 0);  (* Nil timestamp (no stamp) *)
    GC_ITEM_AGE_MS  : UDINT := 60000;   (* Default item tracking timeout [ms] *)
    GC_SPEED_MIN    : LREAL := 0.5;     (* Deadband for speed filter [u/s] *)
    GC_DIST_EPS     : LREAL := 0.01;    (* Distance epsilon [u] *)
    GC_ANG_EPS      : LREAL := 0.03;    (* Angle epsilon [deg] *)

    (* ------------------- Numeric guards ---------------------------------- *)
    GC_REAL_MAX     : LREAL := 1.0E12;  (* Sentinel for "infinite" distance *)
    GC_ID_NONE      : SINT  := 0;       (* "No robot / no feed" identifier *)
END_VAR
