(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Hmi
   -----------------------------------------------------------------------------
   Purpose   : HMI binding area (wizard + operation + diagnostics).
               The HMI reads/writes these variables only; all logic keeps
               its state inside the FBs (fresh mirrors are copied by PRG_SP_TaskFast, service mirrors by PRG_SP_TaskSvc).
   =============================================================================
*)

VAR
    (* ---------------- Commands (HMI writes, logic consumes) ------------- *)
    g_hmiCmd : ST_SP_SysCmd;
    bSaveRecipe  : BOOL;        (* Export g_sRecipeName *)
    bLoadRecipe  : BOOL;        (* Import g_sRecipeName *)
    sRecipeName  : STRING(32) := 'recipe1';
    bAckAll      : BOOL;        (* Alarm acknowledge all *)
    bExportLog   : BOOL;        (* Dump the log ring to file *)

    (* ---------------- Status (logic writes, HMI reads) ------------------ *)
    g_hmiSysStat  : ST_SP_SysStat;
    (* Robot status mirrors for the HMI (one row per robot) 1..GC_ROBOTS *)
    g_astHmiRob   : ARRAY[1..4] OF ST_SP_RobStat;
    (* Feed/conveyor status mirrors for the HMI 1..GC_FEEDS *)
    g_astHmiFeed  : ARRAY[1..8] OF ST_SP_FeedIo;
    (* Camera status mirrors for the HMI 1..GC_CAMS *)
    g_astHmiCam   : ARRAY[1..2] OF ST_SP_VisionStat;
    (* Production counters mirror (OEE page) *)
    g_stHmiStats  : ST_SP_Counters;
    (* Pieces-per-hour KPI computed by Main *)
    rHmiPiecesPerH: LREAL;

    (* ---------------- Diagnostics views (refreshed cyclically) ---------- *)
    g_astHmiAlarm : ARRAY[1..8] OF ST_SP_Alarm;
    (* Last 8 log entries for the HMI list box *)
    g_astHmiLog   : ARRAY[1..8] OF ST_SP_LogEntry;
    sHmiRecipeState : STRING(24);   (* Recipe operation feedback *)

    (* ---------------- Wizard / online adjustment ------------------------ *)
    (* Configuration edits happen directly on the g_ast*Cfg mirrors of
       GVL_SP_Prod while the system is stopped, then PRG applies them via
       the Configure methods (bApplyConfig command below). *)
    bApplyConfig : BOOL;

    (* Camera model preset selector (HW-4, applied by bApplyConfig):
       -1 = Cognex, 1 = Keyence, 2 = GenericTCP, 3 = Simulated,
        0 = keep the current configuration. Uses the ET_SP_CamDrv
       numbering; see FUN_SP_CamPreset. 1..GC_CAMS *)
    g_aiCamModel : ARRAY[1..2] OF SINT;

    (* ---------------- Professional layer (R-16) ------------------------- *)
    (* One-shot commands *)
    bRunSelfTest : BOOL;        (* Run the startup self-test suite *)
    bShiftReset  : BOOL;        (* Reset the OEE shift accumulator *)
    bMaintReset  : BOOL;        (* Reset the maintenance counters *)
    (* OEE snapshot (OEE page) *)
    g_stHmiOee   : ST_SP_OeeView;
    (* Ideal cycle time per piece [ms] (performance reference, editable) *)
    rIdealCycleMs: LREAL := 2000.0;
    (* Maintenance counters and due flags (maintenance page) *)
    g_stHmiMaint : ST_SP_MaintStat;
    (* Self-test result (diagnostics page) *)
    g_stHmiTest  : ST_SP_TestRes;
    (* Advanced collision guard diagnostics (R-05b diagnostics page) 1..GC_ROBOTS *)
    g_astHmiCol  : ARRAY[1..4] OF ST_SP_RobCol;
END_VAR
