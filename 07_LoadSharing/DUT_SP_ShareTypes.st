(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 07_LoadSharing
   Worksheet : DUT - ST_SP_ShareTypes
   -----------------------------------------------------------------------------
   Purpose   : Load sharing data model: robot snapshot for the balancer,
               item offer, and the configuration of the distribution
               strategies (organic, greedy, balanced, manual) with user
               share ratios, robot work ranges and type restrictions.
   =============================================================================
*)

TYPE ST_SP_RobShare :
STRUCT
    iRobotId  : SINT;         (* 1..GC_ROBOTS *)
    bOnline   : BOOL;         (* Group enabled and homed *)
    bFault    : BOOL;         (* Robot in fault (excluded) *)
    bIdle     : BOOL;         (* Ready to accept a job now *)
    uiToolMask: UINT;         (* Bitmask of idle tools (bit i-1 = tool i) *)
    rLoadPct  : LREAL;        (* Estimated busyness [0..1] *)
    udiPicks  : UDINT;        (* Lifetime picks (balancing metric) *)
    udiPlaces : UDINT;        (* Lifetime placements *)
    p2Now     : ST_SP_Pose2D; (* Current world pose (greedy distance metric) *)
END_STRUCT
END_TYPE

TYPE ST_SP_Offer :
STRUCT
    iFeed    : SINT;          (* Feed offering the item 1..GC_FEEDS *)
    uiTypeId : UINT;          (* Product type (0 = unknown) *)
    rBeltOff : LREAL;         (* Current upstream offset [mm] *)
    stW      : ST_SP_Pose2D;  (* Item world pose (greedy metric) *)
    bTarget  : BOOL;          (* TRUE = placement target offer *)
END_STRUCT
END_TYPE

TYPE ST_SP_ShareCfg :
STRUCT
    aeStrat    : ARRAY[1..GC_FEEDS] OF ET_SP_ShareStrategy; (* Per feed *)
    aabManual  : ARRAY[1..GC_FEEDS] OF ARRAY[1..GC_ROBOTS] OF BOOL; (* Manual matrix *)
    arRatio    : ARRAY[1..GC_ROBOTS] OF LREAL;  (* User share ratios (>0) *)
    arRangeFrom: ARRAY[1..GC_FEEDS] OF ARRAY[1..GC_ROBOTS] OF LREAL; (* mm *)
    arRangeTo  : ARRAY[1..GC_FEEDS] OF ARRAY[1..GC_ROBOTS] OF LREAL; (* mm *)
    audTypeMask: ARRAY[1..GC_ROBOTS] OF UDINT;   (* Bit i-1 = type i allowed *)
    eMatch     : ET_SP_MatchMode;               (* Matched/Unmatched/Mixed *)
    bStrictOrder : BOOL;      (* Strict priority order mode (organic) *)
    rPickBias  : LREAL;       (* Pick vs place planning bias [0..1] *)
    aiOutfeedMap : ARRAY[1..GC_FEEDS] OF SINT;  (* Infeed -> outfeed, 0=none *)
END_STRUCT
END_TYPE
