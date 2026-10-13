(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 09_Production
   Worksheet : DUT - ST_SP_SysTypes
   -----------------------------------------------------------------------------
   Purpose   : Production layer data model: feed mirror records (no FB
               references are allowed, so per-feed state flows through
               plain data), system commands/configuration/status and
               dispatch records.
   =============================================================================
*)

TYPE ST_SP_FeedIo :
STRUCT
    (* Mirror of one SP_TrkFeed + its conveyor, filled by PRG_SP_TaskFast *)
    iFeed    : SINT;            (* 1..GC_FEEDS *)
    bUsed    : BOOL;
    rEnc     : LREAL;           (* Current belt encoder [mm] *)
    rSpeed   : LREAL;           (* Signed belt speed [mm/s] *)
    stStat   : ST_SP_TrkStat;   (* Queue statistics *)
    rNearOff : LREAL;           (* Nearest item offset upstream [mm] *)
    stPickLineW: ST_SP_Pose2D;  (* Pick line origin in world (greedy metric) *)
    bCalibOk : BOOL;            (* At least one camera calibrated *)
    bIsOutfeed: BOOL;           (* TRUE = placement feed (pattern engine) *)
END_STRUCT
END_TYPE

TYPE ST_SP_SysCmd :
STRUCT
    (* One-shot system commands (HMI mirror) *)
    bStart   : BOOL;
    bStop    : BOOL;
    bPause   : BOOL;
    bResume  : BOOL;
    bReset   : BOOL;
    bHomeAll : BOOL;
    bDryRun  : BOOL;            (* Trial run lock (system wide) *)
    iStartBatch : SINT;         (* Batch index to start (0 = none) *)
    iStopBatch  : SINT;         (* Batch index to stop (0 = none) *)
    bClearItems : BOOL;         (* Purge all tracking queues *)
END_STRUCT
END_TYPE

TYPE ST_SP_SysCfg :
STRUCT
    (* Resiliency and start policy *)
    tStartStage : TIME;         (* Delay between startup stages *)
    bResilience : BOOL;         (* TRUE = continue on robot loss *)
    bAutoRestart: BOOL;         (* Automatic restart after fault clear *)
    bStopConvsOnPause : BOOL;   (* Stop conveyors during pause *)
    (* Inter-robot zone interlock (R-05, SP_ZoneGuard) *)
    bZoneGuard  : BOOL;         (* TRUE = enforce shared-zone exclusion *)
    (* Advanced crash prevention (R-05b, SP_Collision superset) *)
    bColAdv     : BOOL;         (* TRUE = use SP_Collision (zones + speed + separation) *)
END_STRUCT
END_TYPE

TYPE ST_SP_SysStat :
STRUCT
    eState   : ET_SP_SysState;
    bReady   : BOOL;            (* All stages up, production possible *)
    bRunning : BOOL;
    bPaused  : BOOL;
    bDryRun  : BOOL;
    uiRobotsRun : UINT;         (* Robots in production *)
    uiRobotsFault: UINT;
    udiItemsInSys: UDINT;       (* Items currently tracked (sum) *)
    uiErrId : UINT;
END_STRUCT
END_TYPE

TYPE ST_SP_DispReq :
STRUCT
    (* Dispatch output: one pending reservation request per robot *)
    bReq    : BOOL;             (* Request valid this cycle *)
    iFeed   : SINT;             (* Feed to reserve from *)
    uiTypeId: UINT;             (* Type requested (0 = any) *)
    bTargetOnly : BOOL;         (* TRUE = target reservation (place) *)
    rMaxWeight  : LREAL;        (* Tool capacity [g] *)
    (* R-07 advanced multi-grip: cluster reservation request. Filled by
       PRG_SP_TaskFast from the robot tool configuration when bCluster = TRUE;
       the response then arrives in SP_Dispatch.astClRsp. *)
    bCluster : BOOL;            (* TRUE = cluster reservation (Sync grip) *)
    stCl     : ST_SP_ClReq;     (* Cluster request payload *)
END_STRUCT
END_TYPE

TYPE ST_SP_CancelReq :
STRUCT
    (* Dispatch cancellation: the wiring program releases the records *)
    bCancel : BOOL;             (* Cancel request valid *)
    stJob   : ST_SP_Job;        (* Partial job whose items must be released *)
END_STRUCT
END_TYPE

TYPE ST_SP_StatEv :
STRUCT
    (* Production statistics event (ring buffer element). Written by
       PRG_SP_TaskFast (dispatcher exec block), consumed and applied to
       SP_Stats by PRG_SP_TaskMain. One event per pick / place / cycle. *)
    bCycle  : BOOL;             (* TRUE = cycle-complete event (AddCycle) *)
    bPlace  : BOOL;             (* TRUE = place event, FALSE = pick event *)
    bOk     : BOOL;             (* TRUE = good part, FALSE = NG part *)
    iFeed   : SINT;             (* Feed the event belongs to (1..GC_FEEDS) *)
END_STRUCT
END_TYPE
