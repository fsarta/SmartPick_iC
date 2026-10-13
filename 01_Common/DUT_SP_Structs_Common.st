(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : DUT - ST_SP_Structs_Common
   -----------------------------------------------------------------------------
   Purpose   : Common structures shared by all SmartPick_iC modules:
               version stamp, log entries, alarm records, production counters.
   -----------------------------------------------------------------------------
   Notes     : - All strings have fixed length (no dynamic allocation).
               - No pointers, no references, no FB arrays.
   =============================================================================
*)

TYPE ST_SP_Version :
STRUCT
    sName  : STRING(32);  (* Library name *)
    uiMajor: UINT;        (* Major version *)
    uiMinor: UINT;        (* Minor version *)
    uiBuild: UINT;        (* Build number *)
END_STRUCT
END_TYPE

TYPE ST_SP_LogEntry :
STRUCT
    udiSeq : UDINT;         (* Monotonic sequence number *)
    stTime : Yt_YA_RTC_Struct; (* Wall clock stamp (Yaskawa RTC, v1.8.0) *)
    eLevel : ET_SP_LogLevel;(* Severity *)
    eSrc   : ET_SP_LogSource;(* Originating module *)
    uiCode : UINT;          (* Optional module specific code *)
    sText  : STRING(120);   (* Message text, English *)
END_STRUCT
END_TYPE

TYPE ST_SP_Alarm :
STRUCT
    uiId     : UINT;          (* Unique alarm identifier (>0) *)
    eState   : ET_SP_AckState;(* Active / Acked lifecycle *)
    eLevel   : ET_SP_LogLevel;(* Severity of the alarm *)
    eSrc     : ET_SP_LogSource;(* Originating module *)
    sText    : STRING(80);    (* Alarm text, English *)
    stRaised : Yt_YA_RTC_Struct; (* Wall clock of raise (Yaskawa RTC) *)
    stCleared: Yt_YA_RTC_Struct; (* Wall clock of clear (nil when active) *)
    udiCnt   : UDINT;         (* Number of occurrences *)
END_STRUCT
END_TYPE

TYPE ST_SP_Counters :
STRUCT
    udiPickOk  : UDINT;     (* Successful picks *)
    udiPickNg  : UDINT;     (* Failed picks (verification NG) *)
    udiPlaceOk : UDINT;     (* Successful placements *)
    udiPlaceNg : UDINT;     (* Failed placements *)
    udiCycles  : UDINT;     (* Completed pick/place cycles *)
    udiAlarms  : UDINT;     (* Raised alarms *)
END_STRUCT
END_TYPE

TYPE ST_SP_RetCodeMsg :
STRUCT
    eRc   : ET_SP_RetCode;  (* Return code *)
    uiCode: UINT;           (* Extended module code, 0 = none *)
    sText : STRING(80);     (* Human readable message *)
END_STRUCT
END_TYPE
