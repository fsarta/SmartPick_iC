(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 08_Robot
   Worksheet : DUT - ST_SP_RobotTypes
   -----------------------------------------------------------------------------
   Purpose   : Robot layer data model: tool configuration (multi-cup
               grippers, grip timing, signal mapping), 3-point motion
               path offsets (per robot x feed x type), robot configuration
               (kinematic group binding, segment velocities, precision
               modes, verification policy) and the job structures.
   =============================================================================
*)

TYPE ET_SP_MvKind :
(
    None     := 0,       (* No motion request *)
    Home     := 1,       (* Homing sequence *)
    LinearAbs:= 2,       (* Absolute linear move to static target (MCS) *)
    TrackAbs := 3        (* Tracked move to a belt-synchronized target (PCS when native tracking is on) *)
);
END_TYPE

TYPE ST_SP_BeltFrame :
(* FW-1 native conveyor tracking: per-feed belt frame data consumed by
   SP_Robot / SP_RobMotion to drive the MC_TrackConveyorBelt session.
   Built by SetBeltFrames from the feed configuration (ST_SP_TrkCfg).
   Belt CS convention (PLCopen Part 4 6.6): origin on the belt axis at the
   pick line (feed frame origin), x-axis pointing along the belt travel
   direction, Z up. *)
STRUCT
    bUsed    : BOOL;            (* Feed wired for native tracking (PRG call) *)
    stWorld  : ST_SP_Transf2D;  (* Feed -> world frame transform (frame source) *)
    iDir     : SINT;            (* Belt travel sign (+1 / -1) from the feed config *)
    rOrgX    : LREAL;           (* Belt CS origin X in world/MCS [mm] (feed origin = pick line center) *)
    rOrgY    : LREAL;           (* Belt CS origin Y in world/MCS [mm] *)
    rOrgZ    : LREAL;           (* Belt CS origin Z in world/MCS [mm] = rZBelt *)
    rPhi     : LREAL;           (* Belt CS rotation in world [deg], x-axis along belt travel *)
    rSyncDist: LREAL;           (* TrackOptions.SyncIn.ConveyorDistance [mm], always > 0 (FW 2026.6) *)
    rZBelt   : LREAL;           (* Belt surface height in world [mm] (item Z reference) *)
END_STRUCT
END_TYPE

TYPE ST_SP_TrkSyncIn :
(* FW-1 CONFIRM STAND-IN for the Yaskawa sync-in parameter group of the
   tracking option. Replace with the library type (or map the member path)
   during commissioning - see Firmware/FW_PATCH_ConveyorTracking_IT-EN.md. *)
STRUCT
    ConveyorDistance : LREAL;   (* Sync-in conveyor distance [mm], must be > 0 (FW 2026.6: 0 => error 9006) *)
END_STRUCT
END_TYPE

TYPE ST_SP_TrkOpt :
(* FW-1 CONFIRM STAND-IN for the Yaskawa TrackOptions input struct of
   MC_TrackConveyorBelt. Only the member used by SmartPick is modeled.
   Replace with the installed library type during commissioning. *)
STRUCT
    SyncIn : ST_SP_TrkSyncIn;   (* Sync-in window parameters *)
END_STRUCT
END_TYPE

TYPE ST_SP_ToolCfg :
STRUCT
    bUsed      : BOOL;          (* Tool present *)
    sName      : STRING(16);    (* Human readable tool name *)
    bSuction   : BOOL;          (* TRUE = suction, FALSE = mechanical grip *)
    rMaxWeight : REAL;          (* Payload capacity [g], 0 = unlimited *)
    uiPickOutCh : UINT;         (* Pick output channel (0 = auto robot*tool) *)
    uiPlaceOutCh: UINT;         (* Place output channel (0 = auto) *)
    uiFbkInCh  : UINT;          (* Feedback input channel (0 = auto) *)
    tGrip      : TIME;          (* Grip duration before motion release *)
    tRelease   : TIME;          (* Release duration before departure *)
    rAdvance   : LREAL;         (* Advance timing distance (cut-off margin) [mm] *)
    uiCups     : UINT;          (* Active cups 1..GC_CUPS *)
    bSingleType: BOOL;          (* Tool holds one type per cycle (no mixing) *)
    astCups    : ARRAY[1..GC_CUPS] OF ST_SP_Point3D;  (* Cup offsets rel. TCP [mm] *)
    (* R-07 advanced multi-grip extensions *)
    auiCupFbkCh: ARRAY[1..GC_CUPS] OF UINT; (* Per-cup vacuum feedback channels (0 = tool fbk) *)
    rMatchTol  : LREAL;         (* Cluster cup-to-item match tolerance [mm] *)
    rCapCog    : LREAL;         (* Max CoG offset from TCP [mm], 0 = check off *)
END_STRUCT
END_TYPE

TYPE ST_SP_ToolStat :
STRUCT
    bGripping : BOOL;           (* Grip sequence running *)
    bHolding  : BOOL;           (* Part held (feedback based when available) *)
    bFbk      : BOOL;           (* Raw feedback input *)
    udiPicks  : UDINT;
    udiPlaces : UDINT;
    (* R-07 synchronized multi-grip status (valid after GripSync) *)
    abCupFbk  : ARRAY[1..GC_CUPS] OF BOOL;  (* Per-cup vacuum feedback at grip end *)
    uiCupOk   : UINT;           (* Cups confirmed holding at the last sync grip *)
END_STRUCT
END_TYPE

TYPE ST_SP_PathOff :
STRUCT
    (* 3-point motion path offsets (approach / point / depart) [mm] *)
    rAppDx : LREAL;             (* Approach: X offset from pick/place point *)
    rAppDy : LREAL;             (* Approach: Y offset *)
    rAppDz : LREAL;             (* Approach: Z offset above point *)
    rDepDx : LREAL;             (* Depart: X offset *)
    rDepDy : LREAL;             (* Depart: Y offset *)
    rDepDz : LREAL;             (* Depart: Z offset *)
    rPtDz  : LREAL;             (* Point Z correction (belt tolerance) *)
END_STRUCT
END_TYPE

TYPE ST_SP_RobCfg :
STRUCT
    bUsed    : BOOL;            (* Robot enabled *)
    sName    : STRING(16);      (* Human readable name *)
    uiGroup  : UINT;            (* Firmware kinematic group index (adapter) *)
    uiNumTools : UINT;          (* Configured tools 1..GC_TOOLS *)
    astTools : ARRAY[1..GC_TOOLS] OF ST_SP_ToolCfg;
    (* Segment velocities [mm/s] - segment specific velocity *)
    rVelApp  : LREAL;           (* Approach/depart moves *)
    rVelTrack: LREAL;           (* Tracking pick move (belt synchronized) *)
    rVelPlace: LREAL;           (* Place moves *)
    rAcc     : LREAL;           (* Acceleration [mm/s2] *)
    rDec     : LREAL;           (* Deceleration [mm/s2] *)
    (* Precision modes per segment *)
    ePrecApp  : ET_SP_Precision;
    ePrecPick : ET_SP_Precision;
    ePrecPlace: ET_SP_Precision;
    rZoneTight : LREAL;         (* ZoneTight blending radius [mm] *)
    rZoneWide  : LREAL;         (* ZoneWide blending radius [mm] *)
    (* Work envelope *)
    rZSafe  : LREAL;            (* Safe travel height above belt [mm] *)
    tHomeTimeout : TIME;        (* Homing supervision *)
    (* Multi-gripping *)
    eGripMode : ET_SP_GripMode; (* Sync / Partial / Async *)
    uiMaxGrip : UINT;           (* Max parts per cycle 1..GC_CUPS *)
    (* Verification policy *)
    bVerifyPick  : BOOL;        (* Verify grip feedback at pick *)
    bVerifyPlace : BOOL;        (* Verify release/place *)
    bDeferVerify : BOOL;        (* Deferred: verify holding at place *)
    uiRetries : UINT;           (* Retry count before NG *)
    (* Camera control ownership (resiliency transfer) *)
    abiCamOwner : ARRAY[1..GC_CAMS] OF BOOL;  (* TRUE = this robot owns camera i *)
    (* 3-point path offsets per feed x type *)
    astOff : ARRAY[1..GC_FEEDS] OF ARRAY[1..GC_TYPES] OF ST_SP_PathOff;
END_STRUCT
END_TYPE

TYPE ST_SP_JobItem :
STRUCT
    stItem    : ST_SP_TrkItem;  (* Reserved source item (product or target) *)
    iIdx      : SINT;           (* Queue index in the pick feed *)
    iIdxPlace : SINT;           (* Queue index of the target in the place feed *)
    iFeedPick : SINT;           (* Pick feed (0 for place-only items) *)
    iFeedPlace: SINT;           (* Place feed (0 for pick-only items) *)
    stTgt     : ST_SP_TrkItem;  (* v1.4 placement target snapshot (belt capture data driving the native tracked place) *)
    uiTool    : UINT;           (* Tool used *)
    uiCup     : UINT;           (* Cup used 1..GC_CUPS *)
    p3Pick    : ST_SP_Pose3D;   (* Pick pose (world, predicted) *)
    p3Place   : ST_SP_Pose3D;   (* Place pose (world, target) *)
    bPick     : BOOL;           (* Job includes the pick *)
    bPlace    : BOOL;           (* Job includes the place *)
    bPicked   : BOOL;           (* Progress flags *)
    bPlaced   : BOOL;
    bVerified : BOOL;
    bNg       : BOOL;           (* Item failed (retry exhausted) *)
END_STRUCT
END_TYPE

TYPE ST_SP_Job :
STRUCT
    eKind  : ET_SP_JobKind;     (* Pick / Place / PickPlace *)
    iRobot : SINT;              (* Assigned robot *)
    uiCount: UINT;              (* Valid items 1..GC_CUPS *)
    astItems : ARRAY[1..GC_CUPS] OF ST_SP_JobItem;
    (* R-07 synchronized multi-grip execution *)
    eExec  : ET_SP_GripExec;    (* AsyncCup = sequential, SyncAll = one descent *)
    stSyncPick : ST_SP_Pose3D;  (* Cluster TCP pose at the pick event (SyncAll) *)
END_STRUCT
END_TYPE

TYPE ST_SP_RobCmd :
STRUCT
    bHome   : BOOL;             (* Start homing sequence *)
    bStop   : BOOL;             (* Immediate controlled stop *)
    bReset  : BOOL;             (* Fault reset *)
    bPause  : BOOL;             (* Freeze job (items stay reserved) *)
    bResume : BOOL;             (* Resume from freeze *)
    bDryRun : BOOL;             (* Trial run lock: no grip, raised Z *)
END_STRUCT
END_TYPE

TYPE ST_SP_RobStat :
STRUCT
    eState   : ET_SP_RobState;
    bOnline  : BOOL;
    bReady   : BOOL;            (* Homed, enabled, accepting jobs *)
    bBusy    : BOOL;
    bFault   : BOOL;
    bPaused  : BOOL;
    bHolding : BOOL;            (* Any tool holding *)
    bDryRun  : BOOL;
    uiCurTool: UINT;
    uiCurFeed: SINT;
    (* Place feed of the current job (0 = none; R-05b collision input) *)
    uiCurPlaceFeed : UINT;
    (* v1.4: TRUE = native tracked place armed for the current place item *)
    bTrkPlace : BOOL;
    uiJobCnt : UINT;            (* Items in current job *)
    uiToolMask: UINT;           (* Bit i-1 = tool i idle (balancer input) *)
    p2Now    : ST_SP_Pose2D;    (* Current world pose *)
    udiCycles: UDINT;           (* Completed cycles *)
    udiPicks : UDINT;           (* Lifetime picks (balancer metric) *)
    udiPlaces: UDINT;           (* Lifetime placements *)
    rLoadPct : LREAL;           (* Load metric for the balancer [0..1] *)
    uiErrId  : UINT;            (* Last error code (0 = none) *)
END_STRUCT
END_TYPE
