(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Prod
   -----------------------------------------------------------------------------
   Purpose   : Production data hub.

   Single-writer rules (multi-task build v1.6, see 00_TaskConfig_IT-EN.md):
     - g_stRetain          : written by SP_RetainMgr (VAR RETAIN payload)
     - g_astRobStat        : written by PRG_SP_TaskFast (robot status mirror)
     - g_astFeedIo         : written by PRG_SP_TaskFast (feed mirror)
     - g_aiCamOwner        : written by SP_System (resiliency transfer)
     - configuration arrays: written by HMI editors (offline) and by
       SP_RecipeMgr during import (production stopped)
   Readers: PRG_SP_TaskMain (dispatcher/balancer), PRG_SP_TaskSvc (HMI
   service mirrors via GVL_SP_Hmi publications), recipe export.

   Firmware binding (CONFIRM): g_aAxisEnc / g_aGrp must be bound to the
   encoder axes and kinematic groups configured in the iCube hardware
   catalog. Arrays of STRUCT types are used (no FB arrays exist here).
   =============================================================================
*)

VAR RETAIN
    (* Power-failure continuity blob (managed by SP_RetainMgr) *)
    g_stRetain : ST_SP_RetainData;
END_VAR

VAR
    (* ---------------- Status mirrors (Main writes) --------------------- *)
    g_astRobStat : ARRAY[1..4] OF ST_SP_RobStat;     (* 1..GC_ROBOTS *)
    (* Live feed I/O and status mirrors (written by Main) *)
    g_astFeedIo  : ARRAY[1..8] OF ST_SP_FeedIo;      (* 1..GC_FEEDS *)

    (* ---------------- Camera ownership (resiliency) -------------------- *)
    g_abCamOwnerCfg : ARRAY[1..2] OF ARRAY[1..4] OF BOOL; (* 1..GC_CAMS x 1..GC_ROBOTS *)
    (* Current camera control owner per camera (0 = none) *)
    g_aiCamOwner    : ARRAY[1..2] OF SINT;           (* 1..GC_CAMS *)

    (* ---------------- Configuration mirrors ---------------------------- *)
    g_astConvCfg  : ARRAY[1..8] OF ST_SP_ConvCfg;    (* 1..GC_FEEDS *)
    (* Feed tracking configuration mirrors (recipe-loaded) *)
    g_astFeedCfg  : ARRAY[1..8] OF ST_SP_TrkCfg;     (* 1..GC_FEEDS *)
    (* Camera configuration mirrors (recipe-loaded) *)
    g_astCamCfg   : ARRAY[1..2] OF ST_SP_VisionCfg;  (* 1..GC_CAMS *)
    (* Pattern definitions (recipe-loaded) *)
    g_astPatt     : ARRAY[1..8] OF ST_SP_PattDef;    (* 1..GC_PATT *)
    (* Batch definitions (recipe-loaded) *)
    g_astBatchDef : ARRAY[1..8] OF ST_SP_BatchDef;   (* 1..GC_BATCHES *)
    (* Robot configuration mirrors (defaults + recipe) *)
    g_astRobCfg   : ARRAY[1..4] OF ST_SP_RobCfg;     (* 1..GC_ROBOTS *)
    (* Load-sharing configuration mirror (recipe-loaded) *)
    g_stShareCfg  : ST_SP_ShareCfg;
    (* System configuration mirror (timings, zones, flags) *)
    g_stSysCfg    : ST_SP_SysCfg;

    (* ---------------- Zone interlock map (R-05/R-05b) ------------------- *)
    (* Feed -> zone id 1..GC_ZONES, 0 = unguarded. Consumed by PRG_SP_TaskFast
       (zg.Configure / col.Configure). Default: all zero = interlock off. *)
    g_aiFeedZone  : ARRAY[1..8] OF SINT;             (* 1..GC_FEEDS *)
    (* Advanced collision guard configuration (R-05b, SP_Collision) *)
    g_stColCfg    : ST_SP_ColCfg;
    (* Live conveyor run vector (Main writes; maintenance input) *)
    g_abConvRun   : ARRAY[1..8] OF BOOL;             (* 1..GC_FEEDS *)
    (* Maintenance thresholds (R-16, editable in the HMI editor;
       zero fields are replaced by safe defaults by SP_Maint) *)
    g_stMaintCfg  : ST_SP_MaintCfg;

    (* ---------------- Firmware axis / group bindings (CONFIRM) --------- *)
    g_aAxisEnc : ARRAY[1..8] OF AXIS_REF;        (* Conveyor encoders 1..GC_FEEDS *)
    g_aGrp     : ARRAY[1..4] OF AXES_GROUP_REF; (* Kinematic groups 1..GC_ROBOTS *)

    (* ---------------- Simulation --------------------------------------- *)
    g_bSim : BOOL := TRUE;      (* TRUE = offline simulation mode *)
    g_uiDtMs : UDINT := UDINT#2; (* Period of PRG_SP_TaskFast [ms]
                                    (CONFIRM: task config; set to the real
                                    period of the task running the three
                                    programs in single-task builds) *)
END_VAR
