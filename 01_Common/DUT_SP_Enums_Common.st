(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : DUT - ET_SP_Enums_Common
   -----------------------------------------------------------------------------
   Purpose   : Common enumerations shared by all SmartPick_iC modules.
               One TYPE block per worksheet may be required by the tool;
               if so, split each TYPE into its own DUT worksheet keeping
               the exact names.
   -----------------------------------------------------------------------------
   Notes     : - Enum members are always referenced with the DUT-qualified
                 form ET_Xxx#Member (constants declared in a DDT are only
                 visible inside that DDT in iCube Engineer).
               - No pointers, no references, no actions, no recursion.
   =============================================================================
*)

TYPE ET_SP_RetCode :
(
    Done        := 0,     (* Operation completed successfully *)
    Busy        := 1,     (* Operation in progress, retry later *)
    Idle        := 2,     (* Nothing to do *)
    ErrParam    := 10,    (* Invalid input parameter *)
    ErrState    := 11,    (* Operation not allowed in current state *)
    ErrFull     := 12,    (* Buffer/queue full *)
    ErrEmpty    := 13,    (* Buffer/queue empty *)
    ErrNotFound := 14,    (* Element not found *)
    ErrCom      := 15,    (* Communication error (socket/vision) *)
    ErrIo       := 16,    (* Physical I/O error *)
    ErrBusy     := 17,    (* Resource busy, owned by another consumer *)
    ErrRange    := 18,    (* Value out of admissible range *)
    NotImpl     := 99     (* Feature not implemented on this target *)
);
END_TYPE

TYPE ET_SP_LogLevel :
(
    Debug := 0,           (* Verbose diagnostic level *)
    Info  := 1,           (* Normal operation event *)
    Warn  := 2,           (* Recoverable anomaly *)
    Error := 3            (* Fault requiring operator action *)
);
END_TYPE

TYPE ET_SP_LogSource :
(
    System    := 0,       (* SP_System orchestrator *)
    Robot     := 1,       (* SP_Robot / SP_RobMotion *)
    Feed      := 2,       (* SP_TrkFeed / SP_ItemQueue *)
    Conveyor  := 3,       (* SP_Conveyor *)
    Camera    := 4,       (* SP_VisionCam *)
    Balancer  := 5,       (* SP_LoadBalancer *)
    Batch     := 6,       (* SP_BatchMgr / SP_PatternGen *)
    Persist   := 7,       (* SP_RecipeMgr / SP_RetainMgr *)
    Simulation:= 8,       (* Simulation framework *)
    User      := 9        (* Reserved for integrator code *)
);
END_TYPE

TYPE ET_SP_SysState :
(
    Init       := 0,      (* Power-on, self check, restore retain *)
    Standby    := 10,     (* Configured, waiting for start command *)
    Starting   := 20,     (* Synchronized staged startup *)
    Running    := 30,     (* Automatic production *)
    Pausing    := 40,     (* Draining current motion, freezing jobs *)
    Paused     := 50,     (* Suspended: items and conveyor positions kept *)
    Resuming   := 60,     (* Rebuilding pick plans, restarting conveyors *)
    Stopping   := 70,     (* Controlled shutdown *)
    Stopped    := 80,     (* Safe stop reached *)
    Recovering := 90,     (* Failure resiliency: redistributing after fault *)
    Fault      := 100     (* Unrecoverable system fault *)
);
END_TYPE

TYPE ET_SP_AckState :
(
    Inactive := 0,        (* Alarm not present *)
    Active   := 1,        (* Alarm present, not acknowledged *)
    Acked    := 2         (* Alarm acknowledged (latched until cleared) *)
);
END_TYPE

TYPE ET_SP_ItemState :
(
    Free     := 0,        (* Unused slot *)
    Tracked  := 10,       (* Tracked on conveyor, not reserved *)
    Reserved := 20,       (* Reserved by a robot for picking *)
    Picked   := 30,       (* Physically picked, grip verified *)
    Held     := 40,       (* Held by gripper, place pending *)
    Placed   := 50,       (* Placed (targets only) *)
    Lost     := 60,       (* Lost (picked NG / fell / purged) *)
    TimedOut := 70        (* Exceeded tracking timeout, dropped *)
);
END_TYPE

TYPE ET_SP_RobState :
(
    Init      := 0,       (* Group not enabled *)
    Homing    := 10,      (* Referencing sequence active *)
    Ready     := 20,      (* Homed and enabled, idle at park *)
    WaitJob   := 30,      (* Waiting for job from load balancer *)
    PlanPick  := 40,      (* Planning pick: reserve items, select tool/cups *)
    MoveApp   := 50,      (* Move to pick approach point *)
    TrackPick := 60,      (* Synchronized tracking move to pick point *)
    Grip      := 70,      (* Grip cycle: tool output + feedback + grip time *)
    GripEval  := 71,      (* R-07 sync multi-grip: per-cup evaluation / re-grip *)
    Depart    := 80,      (* Depart/lift from pick point *)
    PlanPlace := 90,      (* Planning place: resolve targets, select cups *)
    MovePlace := 100,     (* Move to place approach point *)
    Place     := 110,     (* Place move to target *)
    Release   := 120,     (* Release cycle *)
    Retreat   := 130,     (* Retreat from place *)
    Verify    := 140,     (* Pick/place verification and retry handling *)
    Paused    := 150,     (* Job frozen, state preserved for resume *)
    Trial     := 160,     (* Trial run (dry run): motion preview only *)
    Fault     := 170      (* Robot fault, excluded from load sharing *)
);
END_TYPE

TYPE ET_SP_Precision :
(
    Exact     := 0,       (* Full deceleration to point, no blending *)
    ZoneTight := 1,       (* Small corner zone for fluid fast paths *)
    ZoneWide  := 2        (* Wide corner zone, maximum throughput *)
);
END_TYPE

TYPE ET_SP_MatchMode :
(
    Matched   := 0,       (* Only items whose type has a defined target *)
    Unmatched := 1,       (* Only free items (bulk picking, no targets) *)
    Mixed     := 2        (* Pick any item, targets get priority *)
);
END_TYPE

TYPE ET_SP_ShareStrategy :
(
    Organic  := 0,        (* Priority ring: first available robot by rank *)
    Greedy   := 1,        (* Least estimated time: distance + queue depth *)
    Balanced := 2,        (* Weighted round robin by share ratios *)
    Manual   := 3         (* Fixed mapping table feed x robot *)
);
END_TYPE

TYPE ET_SP_GripMode :
(
    Sync    := 0,         (* All cups picked/place in one synchronized move *)
    Partial := 1,         (* Groups of cups synchronized, groups sequential *)
    Async   := 2          (* Each cup independent pick, combined place *)
);
END_TYPE

TYPE ET_SP_JobKind :
(
    Pick      := 0,       (* Pick only job (e.g. buffer feed) *)
    Place     := 1,       (* Place only job (e.g. from manual load) *)
    PickPlace := 2        (* Full pick and place job *)
);
END_TYPE

TYPE ET_SP_BatchState :
(
    Idle    := 0,         (* Batch defined but not started *)
    Running := 10,        (* Batch producing targets *)
    Paused  := 20,        (* Batch suspended by system pause *)
    Done    := 30,        (* Quantity reached *)
    Aborted := 40         (* Aborted by operator or system *)
);
END_TYPE

TYPE ET_SP_PattTrig :
(
    Distance   := 0,      (* New pattern every N mm of conveyor travel *)
    Sensor     := 1,      (* New pattern on tray sensor (light barrier) *)
    BatchStart := 2       (* Single pattern at batch start (static pallet) *)
);
END_TYPE

TYPE ET_SP_VisionDrv :
(
    Cognex     := 0,      (* Cognex In-Sight family, ASCII over TCP *)
    Keyence    := 1,      (* Keyence CV/XG family, ASCII over TCP *)
    GenericTCP := 2,      (* User defined ASCII protocol over TCP *)
    Simulated  := 3       (* Internal simulated camera (offline test) *)
);
END_TYPE

TYPE ET_SP_VisionState :
(
    Offline    := 0,      (* Driver idle, socket closed *)
    Connecting := 10,     (* TCP connection attempt in progress *)
    Online     := 20,     (* Connected, ready to trigger *)
    Triggered  := 30,     (* Trigger sent, waiting for reply *)
    Ready      := 50,     (* Result parsed, items available *)
    Fault      := 90      (* Timeout / protocol error *)
);
END_TYPE

TYPE ET_SP_TrigMode :
(
    Distance := 0,        (* Auto trigger every rTrigDist mm of conveyor *)
    External := 1,        (* Trigger from external digital input *)
    Interval := 2,        (* Trigger every tInterval wall-clock time *)
    Manual   := 3         (* Trigger only on explicit command (HMI/PLC) *)
);
END_TYPE

TYPE ET_SP_ConvDriveMode :
(
    Analog    := 0,       (* Conveyour driven by VFD via analog output *)
    ServoAxis := 1,       (* Conveyor driven by servo axis (MC_MoveVelocity) *)
    External  := 2        (* Conveyor speed commanded by external PLC *)
);
END_TYPE

TYPE ET_SP_SocketState :
(
    Closed     := 0,      (* Socket closed *)
    Connecting := 10,     (* Connection in progress *)
    Connected  := 20,     (* TCP established *)
    Fault      := 90      (* Socket error, needs re-open *)
);
END_TYPE

TYPE ET_SP_FileState :
(
    Closed  := 0,         (* No file open *)
    Opening := 10,        (* Open in progress *)
    Open    := 20,        (* File open, ready for transfer *)
    Working := 30,        (* Read/write in progress *)
    Closing := 40,        (* Close in progress *)
    Fault   := 90         (* File system error *)
);
END_TYPE
