(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Package index and iCube Engineer import order (v1.8.0)
   -----------------------------------------------------------------------------
   Target : Yaskawa iC 9226M-EC - iCube Engineer, IEC 61131-3 ST
   Scale  : 4 robots | 8 feeds | 2 cameras | 4 tools/robot | 32 types
   -----------------------------------------------------------------------------
   LIBRARY DEPENDENCIES (add to the iCube project library manager):
     - Motion/PLCopen libraries of the iC 9200 target (MC_* FBs)
     - SysLibSocket / SysLibFile (firmware adapters SP_Socket / SP_FileIo)
     - Y_Yaskawa_Toolbox (NEW v1.8.0): real-time clock FB Y_YA_RealTimeClock
       and data type Yt_YA_RTC_Struct used by GVL_SP_Rtc - CONFIRM the exact
       library name/revision installed on the controller on site
   -----------------------------------------------------------------------------
   IMPORT ORDER (create worksheets in this order; one POU per worksheet,
   split multi-TYPE files if the tool requires it):
     1. Data types (DUT)  : every file named DUT_*  (13_MultiGrip DUT and
                            14_Collision DUT BEFORE the FBs that use them;
                            05_Tracking/08_Robot/09_Production reference
                            the multi-grip types)
     2. Global lists (GVL): GVL_SP_Const, GVL_SP_Vision, GVL_SP_Trk,
                            GVL_SP_Io, GVL_SP_Rtc (NEW v1.8.0: wall clock
                            g_stRtcNow + monotonic tick g_udiTickMs),
                            GVL_SP_Fw, GVL_SP_Prod, GVL_SP_Hmi,
                            GVL_SP_Inst (task-shared FB instances),
                            GVL_SP_Sync (inter-task mailboxes)
     3. Functions (FUN)   : FUN_SP_Utils, FUN_SP_Parse,
                            FUN_SP_RtcToStr, FUN_SP_TickToRtc (NEW v1.8.0,
                            replace the DT-based former timestamp
                            formatter),
                            FUN_SP_ByteCh, FUN_SP_Geometry,
                            FUN_SP_ClusterMath (13_MultiGrip, needed by
                            SP_ItemQueue and SP_Robot),
                            FUN_SP_CamPreset, FUN_SP_RobCfgDefault
     4. Function blocks   : FB_SP_* in dependency order:
                            01_Common, 02_Geometry, 13_MultiGrip
                            (SP_GripPlanner), 03_Conveyor, 04_Vision,
                            05_Tracking, 06_Pattern, 07_LoadSharing,
                            08_Robot, 09_Production, 14_Collision
                            (SP_Collision), 15_Professional (SP_Oee,
                            SP_Maint, SP_SelfTest);
                            methods are embedded in each FB file, marked
                            with "METHOD:" banners - create each method
                            under its parent FB with the exact name.
                            (FB_SP_ZoneGuard lives in 07_LoadSharing and
                            must precede the programs.)
                            NOTE v1.8.0: EVERY METHOD and FUNCTION carries
                            a return type (status / count / executed-ack);
                            statement-style calls remain legal, returns are
                            checked where the outcome matters (linter:
                            scripts/sp_ret_test.py)
     5. Programs (3-task build, v1.6):
                            PRG_SP_TaskFast  -> task SP_Fast_2ms   (2 ms)
                            PRG_SP_TaskMain  -> task SP_Main_10ms  (10 ms)
                            PRG_SP_TaskSvc   -> task SP_Svc_100ms  (100 ms)
                            PRG_SP_ConfigInit (ST-configuration source:
                            writes the eight example configurations of
                            12_Application/CONFIG_EXAMPLES_IT-EN.md into
                            the GVL_SP_Prod mirrors and pulses
                            GVL_SP_Hmi.bApplyConfig; bAutoBoot := TRUE
                            applies iBootCfg at boot, so the cell boots
                            fully configured from structured text - no
                            CSV required; not called by the task programs,
                            assign it to SP_Svc_100ms or SP_Main_10ms)
                            Task creation + assignment rules, CPU budget
                            and single-task compatibility mode:
                            see 00_TaskConfig_IT-EN.md
   -----------------------------------------------------------------------------
   CONFIRM POINTS (firmware binding, see guide ch.6):
     - FB_SP_ConvEncoder  : MC_ReadActualPosition on the encoder axis
     - FB_SP_ConvDrive    : MC_MoveVelocity / analog channel mapping
     - FB_SP_RobMotion    : GroupEnable/Stop/Reset, MC_MoveLinearAbsolute,
                            group pose read; FW-1 CLOSED IN CODE v1.3 -
                            MC_TrackConveyorBelt integrated with runtime
                            selector GVL_SP_Fw.g_eTrkMode; v1.4 adds the
                            native TRACKED PLACE per outfeed feed, enabled
                            by GVL_SP_Fw.g_abPlaceTrack[i]; only 4 enum/
                            struct spellings left to confirm on site
                            -> Firmware/FW_PATCH_ConveyorTracking_IT-EN.md
     - UNITS CONVENTION (v1.7.0): distances in [mm], ALL rotations in
                            [deg] everywhere (variables, configs, HMI,
                            recipes, sim); IEC trig functions receive an
                            explicit GC_DEG2RAD conversion at the call site
                            and FUN_SP_Atan2/FUN_SP_NormAng work in deg
                            (see GVL_SP_Const header)
     - TIME SERVICES (v1.8.0): the IEC DT type is NOT used (not offered
                            by the iCube declaration editor on this target).
                            Wall clock = Y_YA_RealTimeClock (Y_Yaskawa_
                            Toolbox) called ONLY in PRG_SP_TaskSvc section 1,
                            fallback FUN_SP_TickToRtc in simulation / RTC
                            failure; durations = monotonic tick g_udiTickMs
                            advanced ONLY in PRG_SP_TaskFast section 1.
                            RTCString passthrough of the vendor FB is not
                            used; HMI format comes from FUN_SP_RtcToStr.
     - GVL_SP_Fw          : group status injection mode (FW-2), wired in
                            PRG_SP_TaskFast section 6 via GVL_SP_Fw arrays;
                            conveyor tracking mode g_eTrkMode (FW-1)
     - FB_SP_Socket       : SysSocketOpen/Send/Receive/Close
     - FB_SP_FileIo       : SysFileOpen/Read/Write/Close
     - iCube Task Configuration (NEW v1.6): create the three cyclic tasks
                            and assign the programs; keep GVL_SP_Sync
                            per-task periods in sync with the real config
                            -> 00_TaskConfig_IT-EN.md
   =============================================================================
*)
