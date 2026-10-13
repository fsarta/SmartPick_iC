(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : DUT - ST_SP_VisionTypes
   -----------------------------------------------------------------------------
   Purpose   : Vision data model: detected items, camera configuration
               (driver, protocol, trigger policy, multi-feed mapping) and
               runtime status (for HMI and resiliency logic).
   -----------------------------------------------------------------------------
   Camera driver model (feature parity with MotoPick 4):
     - Automatic camera control (trigger policy engine)
     - Detect products and/or targets
     - Flexible camera position (calibration based, no predefined alignment)
     - Multiple feeds per camera (region mapping table)
     - Pluggable drivers: Cognex / Keyence / GenericTCP / Simulated
   =============================================================================
*)

TYPE ST_SP_VisionItem :
STRUCT
    udiId    : UDINT;         (* Globally unique item id (system counter) *)
    uiTypeId : UINT;          (* Product type 1..GC_TYPES, 0 = unknown *)
    p2       : ST_SP_Pose2D;  (* Pose in the producer frame (camera or feed) *)
    rScore   : LREAL;         (* Vision match score [0..1] *)
    rWeight  : LREAL;         (* Part weight [g], 0 = unknown *)
    rBeltPos : LREAL;         (* Belt encoder coordinate at capture [mm] *)
    bTarget  : BOOL;          (* TRUE = placement target, FALSE = product *)
    bValid   : BOOL;          (* Record validity *)
END_STRUCT
END_TYPE

TYPE ST_SP_CamFeedMap :
STRUCT
    iFeed      : SINT;        (* Linked feed 1..GC_FEEDS, 0 = unused *)
    rYmin      : LREAL;       (* Region lower bound (camera Y, along belt) *)
    rYmax      : LREAL;       (* Region upper bound (camera Y, along belt) *)
    rTrigDist  : LREAL;       (* Base trigger distance for this feed [mm] *)
    rRefSpeed  : LREAL;       (* Reference belt speed for auto-scaling [mm/s] *)
    rLastTrig  : LREAL;       (* Belt position at last trigger (runtime) *)
END_STRUCT
END_TYPE

TYPE ST_SP_VisionCfg :
STRUCT
    bUsed      : BOOL;          (* Camera enabled *)
    sName      : STRING(16);    (* Human readable camera name *)
    eDrv       : ET_SP_VisionDrv;(* Selected driver *)
    sIp        : STRING(16);    (* Camera IP address *)
    uiPort     : UINT;          (* Camera TCP port *)
    tTimeout   : TIME;          (* Response timeout *)
    tDelay     : TIME;          (* Delayed acquisition time after trigger *)
    tInterval  : TIME;          (* Periodic trigger interval (Interval mode) *)
    eTrig      : ET_SP_TrigMode;(* Trigger policy *)
    uiMaxItems : UINT;          (* Max items parsed per image *)
    sTrigStr   : STRING(32);    (* Trigger command (Cognex/Keyence/Generic) *)
    sEndTok    : STRING(8);     (* Response end token, '' = idle-timeout based *)
    sSendFmt   : STRING(64);    (* Generic driver send template, {SEQ} macro *)
    sDelim     : STRING(1);     (* Result token delimiter *)
    uiIdxType  : UINT;          (* 1-based token index: type *)
    uiIdxX     : UINT;          (* 1-based token index: X *)
    uiIdxY     : UINT;          (* 1-based token index: Y *)
    uiIdxTh    : UINT;          (* 1-based token index: theta *)
    uiIdxScore : UINT;          (* 1-based token index: score *)
    bThInRad   : BOOL;          (* TRUE = theta from vision in radians (converted to deg); FALSE = degrees *)
    rMinScore  : LREAL;         (* Minimum accepted match score [0..1] *)
    astMap     : ARRAY[1..8] OF ST_SP_CamFeedMap; (* Feed region table 1..GC_FEEDS *)
END_STRUCT
END_TYPE

TYPE ST_SP_VisionStat :
STRUCT
    eState       : ET_SP_VisionState; (* Driver state machine state *)
    bConn        : BOOL;        (* TCP connected *)
    bTrigPending : BOOL;        (* Trigger requested, not yet served *)
    rLastTrigPos : LREAL;       (* Belt position at last trigger [mm] *)
    udiTriggers  : UDINT;       (* Trigger counter *)
    udiItems     : UDINT;       (* Parsed items counter *)
    udiErr       : UDINT;       (* Communication/protocol errors *)
    udiRspMs     : UDINT;       (* Last response round trip [ms] *)
    iOwnerRobot  : SINT;        (* Robot owning camera control (resiliency) *)
END_STRUCT
END_TYPE
