(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : PRG - SP_ConfigInit (v1.5.0)
   -----------------------------------------------------------------------------
   Purpose   : ALL-IN-STRUCTURED-TEXT configuration. EIGHT complete example
               configurations written directly into the GVL_SP_Prod config
               mirrors - NO CSV file, NO file I/O, NO recompile needed to
               switch between them. The old CSV layer (SP_RecipeMgr via
               SysFile) remains available ONLY as an optional HMI backup /
               restore feature for tuned layouts; it is NOT required anymore.

   How it works:
     1) A pulse on bApply (or the boot auto-apply, bAutoBoot/iBootCfg)
        wipes the whole configuration space and writes the selected
        configuration (iCfg = 1..8) field by field in plain ST.
     2) The POU then pulses GVL_SP_Hmi.bApplyConfig: PRG_SP_TaskMain section 1 + PRG_SP_TaskFast section 2
        re-applies everything to the FBs (conv*.Configure, feed*.Configure,
        cam*.Configure, rob*.SetBeltFrames, patt*.Configure, balancer,
        zone/collision guards). This is the same re-apply path used after
        an HMI edit - proven, single-writer, production-stopped only.

   Configuration map (values in USER UNITS - v1.7.0 convention: distances
   in [mm], ALL angles in [deg]; shipped examples use mm/deg):
     1 baseline8     8 feeds, all static (first commissioning)
     2 motopick2x2   2 infeeds + 2 outfeeds, tracked pick, static place
     3 belt2belt     2 infeeds + 2 TRACKED outfeeds (full belt-to-belt)
     4 mixedout      belt-to-belt on outfeed 7, static outfeed 8
     5 onerobot      STRANGE: one robot serves ALL eight feeds
     6 rotrev        STRANGE: reverse belts + 90 deg rotated slots +
                     two-layer trays + tracked place
     7 onecam4feed   STRANGE: ONE camera watches FOUR feeds with four
                     different regions, three high-mix batches
     8 stress        STRANGE: mixed speeds 200..1200, tight windows,
                     zones + advanced collision ON, inverted priorities

   Usage:
     - HMI: write iCfg (1..8), pulse bApply, read bDone / sMsg / iLastCfg.
     - Boot: bAutoBoot = TRUE applies iBootCfg (default 1 = baseline) on
       the first cycle, so the cell boots fully configured from ST.
       Set bAutoBoot = FALSE to boot with an empty configuration.
   Notes:
     - Every configuration sets g_bSim := TRUE (offline first). Set it to
       FALSE on the real cell after commissioning.
     - Camera-to-feed calibrations (astCalib) are pre-filled with the
       identity transform so the simulated cameras work out of the box;
       refine them on the real cell with SP_Calib2D.
     - GVL_SP_Hmi.sRecipeName is set per configuration as a label (used by
       the retain manager and by the OPTIONAL HMI CSV export).
     - Constraints: no pointer / REFERENCE / ACTION / FB-array / recursion.
       One assignment per line; all comments in English.
   =============================================================================
*)

PROGRAM PRG_SP_ConfigInit
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    iCfg      : SINT;           (* Configuration selector 1..8 (see map) *)
    bApply    : BOOL;           (* Rising edge: apply configuration iCfg *)
    bAutoBoot : BOOL := TRUE;   (* TRUE: apply iBootCfg on the first cycle *)
    iBootCfg  : SINT := 1;      (* Configuration id applied at boot *)
END_VAR
VAR_OUTPUT
    bDone     : BOOL;           (* TRUE for one cycle after a successful apply *)
    sMsg      : STRING(80);     (* Human-readable result of the last apply *)
    iLastCfg  : SINT;           (* Last applied configuration id (diagnostic) *)
END_VAR
VAR
    m_bOld    : BOOL;           (* Previous bApply sample (edge detection) *)
    m_bBooted : BOOL := FALSE;  (* Boot auto-apply already done *)
    m_bGo     : BOOL;           (* Internal apply trigger (edge OR boot) *)
    m_iSel    : SINT;           (* Resolved configuration id for this apply *)
    m_i       : SINT;           (* Loop index (feeds / cams / patterns) *)
    m_k       : SINT;           (* Loop index (robots) *)
    (* Wipe templates: declared locals are zero-initialized at boot and
       never written, so they always represent the "empty" configuration. *)
    m_stConvClr : ST_SP_ConvCfg;    (* Zero template for conveyor configs *)
    m_stFeedClr : ST_SP_TrkCfg;     (* Zero template for feed configs *)
    m_stCamClr  : ST_SP_VisionCfg;  (* Zero template for camera configs *)
    m_stPattClr : ST_SP_PattDef;    (* Zero template for pattern defs *)
    m_stBatchClr: ST_SP_BatchDef;   (* Zero template for batch defs *)
    m_stShareClr: ST_SP_ShareCfg;   (* Zero template for load sharing *)
    m_stSysClr  : ST_SP_SysCfg;     (* Zero template for system flags *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bDone := FALSE;                     (* One-shot output, cleared every cycle *)

(* ---------- resolve the trigger: HMI edge OR first-cycle boot ---------- *)
(* Explicit apply wins over the boot auto-apply on the same cycle; any
   successful apply closes the boot window for good (m_bBooted). *)
m_bGo := FALSE;                     (* Recomputed every cycle *)
m_iSel := 0;                        (* 0 = no configuration selected *)
IF bApply AND NOT m_bOld THEN
    m_iSel := iCfg;                 (* HMI / init explicit apply *)
    m_bGo := TRUE;
ELSIF bAutoBoot AND NOT m_bBooted THEN
    m_iSel := iBootCfg;             (* First-cycle boot auto-apply *)
    m_bGo := TRUE;
END_IF
m_bOld := bApply;

IF m_bGo THEN
    m_bBooted := TRUE;              (* Any apply closes the boot window *)

    (* ====================================================================
       1) WIPE the whole configuration space (self-contained configs).
       ==================================================================== *)
    FOR m_i := 1 TO GC_FEEDS DO
        g_astConvCfg[m_i] := m_stConvClr;   (* Empty conveyor config   *)
        g_astFeedCfg[m_i] := m_stFeedClr;   (* Empty feed config       *)
        g_aiFeedZone[m_i] := 0;             (* No zone interlock       *)
    END_FOR
    FOR m_i := 1 TO GC_CAMS DO
        g_astCamCfg[m_i] := m_stCamClr;     (* Empty camera config     *)
        GVL_SP_Hmi.g_aiCamModel[m_i] := 0;  (* 0 = keep, no preset mix *)
    END_FOR
    FOR m_i := 1 TO GC_PATT DO
        g_astPatt[m_i] := m_stPattClr;      (* Empty pattern defs      *)
    END_FOR
    FOR m_i := 1 TO GC_BATCHES DO
        g_astBatchDef[m_i] := m_stBatchClr; (* Empty batch defs        *)
    END_FOR
    g_stShareCfg := m_stShareClr;           (* Empty load sharing      *)
    g_stSysCfg  := m_stSysClr;              (* Guards off, defaults    *)

    (* ====================================================================
       2) NEUTRAL DEFAULTS (each configuration overrides below).
       ==================================================================== *)
    FOR m_i := 1 TO GC_FEEDS DO
        g_stShareCfg.aeStrat[m_i] := ET_SP_ShareStrategy#Greedy;
        g_stShareCfg.aiOutfeedMap[m_i] := 0;            (* No link      *)
        FOR m_k := 1 TO GC_ROBOTS DO
            g_stShareCfg.arRatio[m_k] := 1.0;           (* Equal shares *)
            g_stShareCfg.audTypeMask[m_k] := UDINT#4294967295; (* All   *)
            g_stShareCfg.arRangeFrom[m_i][m_k] := 0.0;  (* Empty range  *)
            g_stShareCfg.arRangeTo[m_i][m_k] := 0.0;    (* = not on feed*)
            g_stShareCfg.aabManual[m_i][m_k] := FALSE;
        END_FOR
    END_FOR
    g_stShareCfg.eMatch := ET_SP_MatchMode#Mixed;       (* Targets first *)
    g_stShareCfg.bStrictOrder := FALSE;                 (* Free priority *)
    g_stShareCfg.rPickBias := 0.5;                      (* Balanced      *)
    GVL_SP_Fw.g_eTrkMode := 0;                          (* Static pick   *)
    FOR m_i := 1 TO GC_FEEDS DO
        GVL_SP_Fw.g_abPlaceTrack[m_i] := FALSE;         (* Static place  *)
    END_FOR
    g_bSim := TRUE;                     (* Offline first; FALSE on cell  *)

    (* ====================================================================
       3) SELECTED CONFIGURATION.
       ==================================================================== *)
    CASE m_iSel OF

(* -----------------------------------------------------------------------
   CONFIG 1 - baseline8: full 8-feed cell, ALL STATIC.
   First commissioning: I/O checkout, camera framing, SP_Calib2D.
   Mirrors the former Demo_Sim recipe data (regression anchor).
   ----------------------------------------------------------------------- *)
        1:
            (* ---- Conveyors + feeds: 6 infeeds + 2 outfeeds ---- *)
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 500.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;  (* dx=0, dy=0, rot=0 *)
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 500.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[3].bUsed := TRUE;  g_astConvCfg[3].sName := 'inf_3';
            g_astConvCfg[3].rEncScale := 0.1;   g_astConvCfg[3].iDir := 1;
            g_astConvCfg[3].rMaxSpeed := 500.0; g_astConvCfg[3].rWinStart := 300.0;
            g_astConvCfg[3].rWinLen := 600.0;   g_astConvCfg[3].rSlowAhead := 200.0;
            g_astConvCfg[3].rStopAhead := 100.0; g_astConvCfg[3].rSlowFactor := 0.4;
            g_astConvCfg[3].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[3].bUsed := TRUE;  g_astFeedCfg[3].sName := 'inf_3';
            g_astFeedCfg[3].iDir := 1;      g_astFeedCfg[3].rWinStart := 300.0;
            g_astFeedCfg[3].rWinLen := 600.0;  g_astFeedCfg[3].rPickAhead := 350.0;
            g_astFeedCfg[3].tTimeout := T#8s;  g_astFeedCfg[3].rZBelt := 850.0;
            g_astFeedCfg[3].stWorld.rDy := -500.0;
            g_astFeedCfg[3].stWorld.rScale := 1.0;
            g_astFeedCfg[3].stWorld.bValid := TRUE;

            g_astConvCfg[4].bUsed := TRUE;  g_astConvCfg[4].sName := 'inf_4';
            g_astConvCfg[4].rEncScale := 0.1;   g_astConvCfg[4].iDir := 1;
            g_astConvCfg[4].rMaxSpeed := 500.0; g_astConvCfg[4].rWinStart := 300.0;
            g_astConvCfg[4].rWinLen := 600.0;   g_astConvCfg[4].rSlowAhead := 200.0;
            g_astConvCfg[4].rStopAhead := 100.0; g_astConvCfg[4].rSlowFactor := 0.4;
            g_astConvCfg[4].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[4].bUsed := TRUE;  g_astFeedCfg[4].sName := 'inf_4';
            g_astFeedCfg[4].iDir := 1;      g_astFeedCfg[4].rWinStart := 300.0;
            g_astFeedCfg[4].rWinLen := 600.0;  g_astFeedCfg[4].rPickAhead := 350.0;
            g_astFeedCfg[4].tTimeout := T#8s;  g_astFeedCfg[4].rZBelt := 850.0;
            g_astFeedCfg[4].stWorld.rDx := 2500.0;
            g_astFeedCfg[4].stWorld.rScale := 1.0;
            g_astFeedCfg[4].stWorld.bValid := TRUE;

            g_astConvCfg[5].bUsed := TRUE;  g_astConvCfg[5].sName := 'inf_5';
            g_astConvCfg[5].rEncScale := 0.1;   g_astConvCfg[5].iDir := 1;
            g_astConvCfg[5].rMaxSpeed := 500.0; g_astConvCfg[5].rWinStart := 300.0;
            g_astConvCfg[5].rWinLen := 600.0;   g_astConvCfg[5].rSlowAhead := 200.0;
            g_astConvCfg[5].rStopAhead := 100.0; g_astConvCfg[5].rSlowFactor := 0.4;
            g_astConvCfg[5].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[5].bUsed := TRUE;  g_astFeedCfg[5].sName := 'inf_5';
            g_astFeedCfg[5].iDir := 1;      g_astFeedCfg[5].rWinStart := 300.0;
            g_astFeedCfg[5].rWinLen := 600.0;  g_astFeedCfg[5].rPickAhead := 350.0;
            g_astFeedCfg[5].tTimeout := T#8s;  g_astFeedCfg[5].rZBelt := 850.0;
            g_astFeedCfg[5].stWorld.rDx := 2500.0;  g_astFeedCfg[5].stWorld.rDy := 500.0;
            g_astFeedCfg[5].stWorld.rScale := 1.0;
            g_astFeedCfg[5].stWorld.bValid := TRUE;

            g_astConvCfg[6].bUsed := TRUE;  g_astConvCfg[6].sName := 'inf_6';
            g_astConvCfg[6].rEncScale := 0.1;   g_astConvCfg[6].iDir := 1;
            g_astConvCfg[6].rMaxSpeed := 500.0; g_astConvCfg[6].rWinStart := 300.0;
            g_astConvCfg[6].rWinLen := 600.0;   g_astConvCfg[6].rSlowAhead := 200.0;
            g_astConvCfg[6].rStopAhead := 100.0; g_astConvCfg[6].rSlowFactor := 0.4;
            g_astConvCfg[6].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[6].bUsed := TRUE;  g_astFeedCfg[6].sName := 'inf_6';
            g_astFeedCfg[6].iDir := 1;      g_astFeedCfg[6].rWinStart := 300.0;
            g_astFeedCfg[6].rWinLen := 600.0;  g_astFeedCfg[6].rPickAhead := 350.0;
            g_astFeedCfg[6].tTimeout := T#8s;  g_astFeedCfg[6].rZBelt := 850.0;
            g_astFeedCfg[6].stWorld.rDx := 2500.0;  g_astFeedCfg[6].stWorld.rDy := -500.0;
            g_astFeedCfg[6].stWorld.rScale := 1.0;
            g_astFeedCfg[6].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1250.0;  g_astFeedCfg[7].stWorld.rDy := 1000.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 300.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 3750.0;  g_astFeedCfg[8].stWorld.rDy := -1000.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            (* ---- Identity camera calibrations on every used feed ---- *)
            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            (* ---- Two simulated cameras, distance-triggered ---- *)
            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_a';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#12;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;  g_astCamCfg[1].astMap[2].iFeed := 2;
            g_astCamCfg[1].astMap[3].iFeed := 3;  g_astCamCfg[1].astMap[4].iFeed := 4;
            g_astCamCfg[1].astMap[5].iFeed := 5;  g_astCamCfg[1].astMap[6].iFeed := 6;
            FOR m_i := 1 TO 6 DO
                g_astCamCfg[1].astMap[m_i].rYmin := 0.0;
                g_astCamCfg[1].astMap[m_i].rYmax := 600.0;
                g_astCamCfg[1].astMap[m_i].rTrigDist := 300.0;
                g_astCamCfg[1].astMap[m_i].rRefSpeed := 500.0;
            END_FOR
            g_astCamCfg[2].bUsed := TRUE;   g_astCamCfg[2].sName := 'cam_b';
            g_astCamCfg[2].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[2].sIp := '127.0.0.1';  g_astCamCfg[2].uiPort := UINT#0;
            g_astCamCfg[2].tTimeout := T#800ms; g_astCamCfg[2].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[2].uiMaxItems := UINT#12;   g_astCamCfg[2].bThInRad := FALSE;
            g_astCamCfg[2].rMinScore := 0.8;
            g_astCamCfg[2].astMap[1].iFeed := 1;
            g_astCamCfg[2].astMap[1].rYmin := 0.0;  g_astCamCfg[2].astMap[1].rYmax := 600.0;
            g_astCamCfg[2].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[2].astMap[1].rRefSpeed := 500.0;

            (* ---- Patterns: 4x4 tray, 3x3 two-layer, 5x3 tray ---- *)
            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray3x3_2L';
            g_astPatt[2].uiRows := UINT#3;  g_astPatt[2].uiCols := UINT#3;
            g_astPatt[2].rDx := 150.0;      g_astPatt[2].rDy := 150.0;
            g_astPatt[2].pBase.rX := 200.0; g_astPatt[2].pBase.rY := 200.0;
            g_astPatt[2].uiLayers := UINT#2;    g_astPatt[2].rLayerH := 60.0;
            g_astPatt[2].rZBase := 950.0;
            g_astPatt[3].bUsed := TRUE;     g_astPatt[3].sName := 'tray4x4b';
            g_astPatt[3].uiRows := UINT#4;  g_astPatt[3].uiCols := UINT#4;
            g_astPatt[3].rDx := 110.0;      g_astPatt[3].rDy := 110.0;
            g_astPatt[3].pBase.rX := 150.0; g_astPatt[3].pBase.rY := 150.0;
            g_astPatt[3].uiLayers := UINT#1;    g_astPatt[3].rZBase := 950.0;
            g_astPatt[3].rTrigDist := 450.0;
            g_astPatt[4].bUsed := TRUE;     g_astPatt[4].sName := 'tray5x3';
            g_astPatt[4].uiRows := UINT#5;  g_astPatt[4].uiCols := UINT#3;
            g_astPatt[4].rDx := 120.0;      g_astPatt[4].rDy := 120.0;
            g_astPatt[4].pBase.rX := 160.0; g_astPatt[4].pBase.rY := 160.0;
            g_astPatt[4].uiLayers := UINT#1;    g_astPatt[4].rZBase := 950.0;
            g_astPatt[4].rTrigDist := 500.0;

            (* ---- Batches: two per outfeed, mixed types ---- *)
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_main7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#8;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#8;
            g_astBatchDef[1].udiQty := UDINT#48;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_mix7';
            g_astBatchDef[2].iOutFeed := 7; g_astBatchDef[2].uiPattId := UINT#2;
            g_astBatchDef[2].aiMix[1] := UINT#5;    g_astBatchDef[2].aiMixCnt[1] := UINT#9;
            g_astBatchDef[2].udiQty := UDINT#27;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[2].iPriority := 5;
            g_astBatchDef[3].bUsed := TRUE; g_astBatchDef[3].sName := 'b3_main8';
            g_astBatchDef[3].iOutFeed := 8; g_astBatchDef[3].uiPattId := UINT#3;
            g_astBatchDef[3].aiMix[1] := UINT#3;    g_astBatchDef[3].aiMixCnt[1] := UINT#8;
            g_astBatchDef[3].aiMix[2] := UINT#4;    g_astBatchDef[3].aiMixCnt[2] := UINT#8;
            g_astBatchDef[3].udiQty := UDINT#64;
            g_astBatchDef[3].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[3].iPriority := 10;
            g_astBatchDef[4].bUsed := TRUE; g_astBatchDef[4].sName := 'b4_mix8';
            g_astBatchDef[4].iOutFeed := 8; g_astBatchDef[4].uiPattId := UINT#4;
            g_astBatchDef[4].aiMix[1] := UINT#6;    g_astBatchDef[4].aiMixCnt[1] := UINT#7;
            g_astBatchDef[4].udiQty := UDINT#45;
            g_astBatchDef[4].eTrig := ET_SP_PattTrig#Sensor;
            g_astBatchDef[4].iPriority := 5;

            (* ---- Load sharing: two-robot neighborhoods per feed ---- *)
            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 7;
            g_stShareCfg.aiOutfeedMap[3] := 7;  g_stShareCfg.aiOutfeedMap[4] := 8;
            g_stShareCfg.aiOutfeedMap[5] := 8;  g_stShareCfg.aiOutfeedMap[6] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[3][m_k] := 600.0;
            END_FOR
            FOR m_k := 3 TO 4 DO
                g_stShareCfg.arRangeTo[4][m_k] := 600.0;
            END_FOR
            FOR m_k := 3 TO 4 DO
                g_stShareCfg.arRangeTo[5][m_k] := 600.0;
            END_FOR
            FOR m_k := 3 TO 4 DO
                g_stShareCfg.arRangeTo[6][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: all static (baseline) ---- *)
            GVL_SP_Hmi.sRecipeName := 'cfg1_baseline';
            sMsg := 'CFG1 baseline8: 8 feeds, all static, 2 sim cams';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 2 - motopick2x2: 2 infeeds + 2 outfeeds, TRACKED PICK + static
   place (classic MotoPick 4). Two Cognex cameras on the real cell IPs.
   Mirrors the former Demo_Line1 recipe data (regression anchor).
   ----------------------------------------------------------------------- *)
        2:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 500.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 500.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1250.0;  g_astFeedCfg[7].stWorld.rDy := 1000.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 300.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 3750.0;  g_astFeedCfg[8].stWorld.rDy := -1000.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            (* ---- Identity calibrations (refine with SP_Calib2D) ---- *)
            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            (* ---- Two Cognex cameras (adapt IPs to the site) ---- *)
            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_cgx1';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Cognex;
            g_astCamCfg[1].sIp := '192.168.10.10';  g_astCamCfg[1].uiPort := UINT#5000;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#12;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;
            g_astCamCfg[1].astMap[1].rYmin := 0.0;  g_astCamCfg[1].astMap[1].rYmax := 600.0;
            g_astCamCfg[1].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[1].astMap[1].rRefSpeed := 500.0;
            g_astCamCfg[2].bUsed := TRUE;   g_astCamCfg[2].sName := 'cam_cgx2';
            g_astCamCfg[2].eDrv := ET_SP_CamDrv#Cognex;
            g_astCamCfg[2].sIp := '192.168.10.11';  g_astCamCfg[2].uiPort := UINT#5000;
            g_astCamCfg[2].tTimeout := T#800ms; g_astCamCfg[2].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[2].uiMaxItems := UINT#12;   g_astCamCfg[2].bThInRad := FALSE;
            g_astCamCfg[2].rMinScore := 0.8;
            g_astCamCfg[2].astMap[1].iFeed := 2;
            g_astCamCfg[2].astMap[1].rYmin := 0.0;  g_astCamCfg[2].astMap[1].rYmax := 600.0;
            g_astCamCfg[2].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[2].astMap[1].rRefSpeed := 500.0;

            (* ---- Patterns + batches (trays static on the outfeeds) ---- *)
            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray3x3_2L';
            g_astPatt[2].uiRows := UINT#3;  g_astPatt[2].uiCols := UINT#3;
            g_astPatt[2].rDx := 150.0;      g_astPatt[2].rDy := 150.0;
            g_astPatt[2].pBase.rX := 200.0; g_astPatt[2].pBase.rY := 200.0;
            g_astPatt[2].uiLayers := UINT#2;    g_astPatt[2].rLayerH := 60.0;
            g_astPatt[2].rZBase := 950.0;
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_main7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#8;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#8;
            g_astBatchDef[1].udiQty := UDINT#48;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_main8';
            g_astBatchDef[2].iOutFeed := 8; g_astBatchDef[2].uiPattId := UINT#2;
            g_astBatchDef[2].aiMix[1] := UINT#5;    g_astBatchDef[2].aiMixCnt[1] := UINT#9;
            g_astBatchDef[2].udiQty := UDINT#27;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#Sensor;
            g_astBatchDef[2].iPriority := 5;

            (* ---- Load sharing + links ---- *)
            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: flying pick, static place ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Hmi.sRecipeName := 'cfg2_motopick';
            sMsg := 'CFG2 motopick2x2: tracked pick, static place, 2 Cognex';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 3 - belt2belt: 2 infeeds + 2 TRACKED outfeeds (full belt-to-belt,
   maximum throughput, zero line stops). Mirrors the former Demo_Belt2Belt
   recipe data (regression anchor).
   ----------------------------------------------------------------------- *)
        3:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 500.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 500.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            (* Outfeeds keep running: trays reached on the fly *)
            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7_trk';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7_trk';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1100.0;  g_astFeedCfg[7].stWorld.rDy := -500.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8_trk';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 300.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8_trk';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 1100.0;  g_astFeedCfg[8].stWorld.rDy := 1100.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_a';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#12;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;
            g_astCamCfg[1].astMap[1].rYmin := 0.0;  g_astCamCfg[1].astMap[1].rYmax := 600.0;
            g_astCamCfg[1].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[1].astMap[1].rRefSpeed := 500.0;
            g_astCamCfg[2].bUsed := TRUE;   g_astCamCfg[2].sName := 'cam_b';
            g_astCamCfg[2].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[2].sIp := '127.0.0.1';  g_astCamCfg[2].uiPort := UINT#0;
            g_astCamCfg[2].tTimeout := T#800ms; g_astCamCfg[2].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[2].uiMaxItems := UINT#12;   g_astCamCfg[2].bThInRad := FALSE;
            g_astCamCfg[2].rMinScore := 0.8;
            g_astCamCfg[2].astMap[1].iFeed := 2;
            g_astCamCfg[2].astMap[1].rYmin := 0.0;  g_astCamCfg[2].astMap[1].rYmax := 600.0;
            g_astCamCfg[2].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[2].astMap[1].rRefSpeed := 500.0;

            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray3x3_2L';
            g_astPatt[2].uiRows := UINT#3;  g_astPatt[2].uiCols := UINT#3;
            g_astPatt[2].rDx := 150.0;      g_astPatt[2].rDy := 150.0;
            g_astPatt[2].pBase.rX := 200.0; g_astPatt[2].pBase.rY := 200.0;
            g_astPatt[2].uiLayers := UINT#2;    g_astPatt[2].rLayerH := 60.0;
            g_astPatt[2].rZBase := 950.0;
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_main7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#8;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#8;
            g_astBatchDef[1].udiQty := UDINT#48;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_main8';
            g_astBatchDef[2].iOutFeed := 8; g_astBatchDef[2].uiPattId := UINT#2;
            g_astBatchDef[2].aiMix[1] := UINT#5;    g_astBatchDef[2].aiMixCnt[1] := UINT#9;
            g_astBatchDef[2].udiQty := UDINT#27;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[2].iPriority := 5;

            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: flying pick AND tracked place on 7 + 8 ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Fw.g_abPlaceTrack[7] := TRUE;
            GVL_SP_Fw.g_abPlaceTrack[8] := TRUE;
            GVL_SP_Hmi.sRecipeName := 'cfg3_belt2belt';
            sMsg := 'CFG3 belt2belt: tracked pick + tracked place on 7/8';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 4 - mixedout: belt-to-belt ONLY on outfeed 7; outfeed 8 carries
   static pallets (or its encoder is not wired yet). Same layout as CFG 3,
   only the per-feed place selector differs.
   ----------------------------------------------------------------------- *)
        4:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 500.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 500.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7_trk';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7_trk';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1100.0;  g_astFeedCfg[7].stWorld.rDy := -500.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8_sta';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 300.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8_sta';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 1100.0;  g_astFeedCfg[8].stWorld.rDy := 1100.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_a';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#12;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;
            g_astCamCfg[1].astMap[1].rYmin := 0.0;  g_astCamCfg[1].astMap[1].rYmax := 600.0;
            g_astCamCfg[1].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[1].astMap[1].rRefSpeed := 500.0;
            g_astCamCfg[2].bUsed := TRUE;   g_astCamCfg[2].sName := 'cam_b';
            g_astCamCfg[2].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[2].sIp := '127.0.0.1';  g_astCamCfg[2].uiPort := UINT#0;
            g_astCamCfg[2].tTimeout := T#800ms; g_astCamCfg[2].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[2].uiMaxItems := UINT#12;   g_astCamCfg[2].bThInRad := FALSE;
            g_astCamCfg[2].rMinScore := 0.8;
            g_astCamCfg[2].astMap[1].iFeed := 2;
            g_astCamCfg[2].astMap[1].rYmin := 0.0;  g_astCamCfg[2].astMap[1].rYmax := 600.0;
            g_astCamCfg[2].astMap[1].rTrigDist := 300.0;
            g_astCamCfg[2].astMap[1].rRefSpeed := 500.0;

            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray3x3_2L';
            g_astPatt[2].uiRows := UINT#3;  g_astPatt[2].uiCols := UINT#3;
            g_astPatt[2].rDx := 150.0;      g_astPatt[2].rDy := 150.0;
            g_astPatt[2].pBase.rX := 200.0; g_astPatt[2].pBase.rY := 200.0;
            g_astPatt[2].uiLayers := UINT#2;    g_astPatt[2].rLayerH := 60.0;
            g_astPatt[2].rZBase := 950.0;
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_main7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#8;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#8;
            g_astBatchDef[1].udiQty := UDINT#48;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_main8';
            g_astBatchDef[2].iOutFeed := 8; g_astBatchDef[2].uiPattId := UINT#2;
            g_astBatchDef[2].aiMix[1] := UINT#5;    g_astBatchDef[2].aiMixCnt[1] := UINT#9;
            g_astBatchDef[2].udiQty := UDINT#27;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[2].iPriority := 5;

            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: pick tracked, place tracked on 7 ONLY ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Fw.g_abPlaceTrack[7] := TRUE;
            GVL_SP_Hmi.sRecipeName := 'cfg4_mixedout';
            sMsg := 'CFG4 mixedout: outfeed 7 tracked, outfeed 8 static';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 5 - onerobot (STRANGE): robot 1 serves ALL EIGHT feeds. Robots
   2..4 are excluded by empty work ranges on every feed; ratio 10:0.01
   emphasizes the single-robot policy in Balanced mode too. Tracked pick.
   ----------------------------------------------------------------------- *)
        5:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 400.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 400.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[3].bUsed := TRUE;  g_astConvCfg[3].sName := 'inf_3';
            g_astConvCfg[3].rEncScale := 0.1;   g_astConvCfg[3].iDir := 1;
            g_astConvCfg[3].rMaxSpeed := 400.0; g_astConvCfg[3].rWinStart := 300.0;
            g_astConvCfg[3].rWinLen := 600.0;   g_astConvCfg[3].rSlowAhead := 200.0;
            g_astConvCfg[3].rStopAhead := 100.0; g_astConvCfg[3].rSlowFactor := 0.4;
            g_astConvCfg[3].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[3].bUsed := TRUE;  g_astFeedCfg[3].sName := 'inf_3';
            g_astFeedCfg[3].iDir := 1;      g_astFeedCfg[3].rWinStart := 300.0;
            g_astFeedCfg[3].rWinLen := 600.0;  g_astFeedCfg[3].rPickAhead := 350.0;
            g_astFeedCfg[3].tTimeout := T#8s;  g_astFeedCfg[3].rZBelt := 850.0;
            g_astFeedCfg[3].stWorld.rDy := -500.0;
            g_astFeedCfg[3].stWorld.rScale := 1.0;
            g_astFeedCfg[3].stWorld.bValid := TRUE;

            g_astConvCfg[4].bUsed := TRUE;  g_astConvCfg[4].sName := 'inf_4';
            g_astConvCfg[4].rEncScale := 0.1;   g_astConvCfg[4].iDir := 1;
            g_astConvCfg[4].rMaxSpeed := 400.0; g_astConvCfg[4].rWinStart := 300.0;
            g_astConvCfg[4].rWinLen := 600.0;   g_astConvCfg[4].rSlowAhead := 200.0;
            g_astConvCfg[4].rStopAhead := 100.0; g_astConvCfg[4].rSlowFactor := 0.4;
            g_astConvCfg[4].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[4].bUsed := TRUE;  g_astFeedCfg[4].sName := 'inf_4';
            g_astFeedCfg[4].iDir := 1;      g_astFeedCfg[4].rWinStart := 300.0;
            g_astFeedCfg[4].rWinLen := 600.0;  g_astFeedCfg[4].rPickAhead := 350.0;
            g_astFeedCfg[4].tTimeout := T#8s;  g_astFeedCfg[4].rZBelt := 850.0;
            g_astFeedCfg[4].stWorld.rDx := 2500.0;
            g_astFeedCfg[4].stWorld.rScale := 1.0;
            g_astFeedCfg[4].stWorld.bValid := TRUE;

            g_astConvCfg[5].bUsed := TRUE;  g_astConvCfg[5].sName := 'inf_5';
            g_astConvCfg[5].rEncScale := 0.1;   g_astConvCfg[5].iDir := 1;
            g_astConvCfg[5].rMaxSpeed := 400.0; g_astConvCfg[5].rWinStart := 300.0;
            g_astConvCfg[5].rWinLen := 600.0;   g_astConvCfg[5].rSlowAhead := 200.0;
            g_astConvCfg[5].rStopAhead := 100.0; g_astConvCfg[5].rSlowFactor := 0.4;
            g_astConvCfg[5].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[5].bUsed := TRUE;  g_astFeedCfg[5].sName := 'inf_5';
            g_astFeedCfg[5].iDir := 1;      g_astFeedCfg[5].rWinStart := 300.0;
            g_astFeedCfg[5].rWinLen := 600.0;  g_astFeedCfg[5].rPickAhead := 350.0;
            g_astFeedCfg[5].tTimeout := T#8s;  g_astFeedCfg[5].rZBelt := 850.0;
            g_astFeedCfg[5].stWorld.rDx := 2500.0;  g_astFeedCfg[5].stWorld.rDy := 500.0;
            g_astFeedCfg[5].stWorld.rScale := 1.0;
            g_astFeedCfg[5].stWorld.bValid := TRUE;

            g_astConvCfg[6].bUsed := TRUE;  g_astConvCfg[6].sName := 'inf_6';
            g_astConvCfg[6].rEncScale := 0.1;   g_astConvCfg[6].iDir := 1;
            g_astConvCfg[6].rMaxSpeed := 400.0; g_astConvCfg[6].rWinStart := 300.0;
            g_astConvCfg[6].rWinLen := 600.0;   g_astConvCfg[6].rSlowAhead := 200.0;
            g_astConvCfg[6].rStopAhead := 100.0; g_astConvCfg[6].rSlowFactor := 0.4;
            g_astConvCfg[6].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[6].bUsed := TRUE;  g_astFeedCfg[6].sName := 'inf_6';
            g_astFeedCfg[6].iDir := 1;      g_astFeedCfg[6].rWinStart := 300.0;
            g_astFeedCfg[6].rWinLen := 600.0;  g_astFeedCfg[6].rPickAhead := 350.0;
            g_astFeedCfg[6].tTimeout := T#8s;  g_astFeedCfg[6].rZBelt := 850.0;
            g_astFeedCfg[6].stWorld.rDx := 2500.0;  g_astFeedCfg[6].stWorld.rDy := -500.0;
            g_astFeedCfg[6].stWorld.rScale := 1.0;
            g_astFeedCfg[6].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1250.0;  g_astFeedCfg[7].stWorld.rDy := 1000.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 300.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 3750.0;  g_astFeedCfg[8].stWorld.rDy := -1000.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            (* ONE camera wide enough to watch four infeeds at once *)
            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_wide';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#16;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;  g_astCamCfg[1].astMap[2].iFeed := 2;
            g_astCamCfg[1].astMap[3].iFeed := 3;  g_astCamCfg[1].astMap[4].iFeed := 4;
            FOR m_i := 1 TO 4 DO
                g_astCamCfg[1].astMap[m_i].rYmin := 0.0;
                g_astCamCfg[1].astMap[m_i].rYmax := 600.0;
                g_astCamCfg[1].astMap[m_i].rTrigDist := 300.0;
                g_astCamCfg[1].astMap[m_i].rRefSpeed := 400.0;
            END_FOR

            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_main7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#8;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#8;
            g_astBatchDef[1].udiQty := UDINT#48;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;

            (* ---- STRANGE: robot 1 on all feeds, robots 2..4 off ---- *)
            g_stShareCfg.arRatio[1] := 10.0;
            g_stShareCfg.arRatio[2] := 0.01;
            g_stShareCfg.arRatio[3] := 0.01;
            g_stShareCfg.arRatio[4] := 0.01;
            FOR m_i := 1 TO 3 DO
                g_stShareCfg.aiOutfeedMap[m_i] := 7;
                g_stShareCfg.arRangeTo[m_i][1] := 600.0;  (* Only robot 1 *)
            END_FOR
            FOR m_i := 4 TO 6 DO
                g_stShareCfg.aiOutfeedMap[m_i] := 8;
                g_stShareCfg.arRangeTo[m_i][1] := 600.0;  (* Only robot 1 *)
            END_FOR

            (* Second batch on the spare outfeed 8 (same single robot) *)
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_spare8';
            g_astBatchDef[2].iOutFeed := 8; g_astBatchDef[2].uiPattId := UINT#1;
            g_astBatchDef[2].aiMix[1] := UINT#3;    g_astBatchDef[2].aiMixCnt[1] := UINT#8;
            g_astBatchDef[2].aiMix[2] := UINT#4;    g_astBatchDef[2].aiMixCnt[2] := UINT#8;
            g_astBatchDef[2].udiQty := UDINT#32;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[2].iPriority := 5;

            (* ---- Tracking: flying pick, static place ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Hmi.sRecipeName := 'cfg5_onerobot';
            sMsg := 'CFG5 onerobot: robot 1 serves all 8 feeds alone';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 6 - rotrev (STRANGE): REVERSE belt direction on both infeeds,
   90-degree ROTATED tray slots (rotstep), TWO-layer trays on the outfeed,
   tracked pick AND tracked place on outfeed 7. Exercises the full frame
   math: negative direction sign, rotated product yaw, layer Z stacking.
   ----------------------------------------------------------------------- *)
        6:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'rev_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := -1;
            g_astConvCfg[1].rMaxSpeed := 350.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'rev_1';
            g_astFeedCfg[1].iDir := -1;     g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'rev_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := -1;
            g_astConvCfg[2].rMaxSpeed := 350.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'rev_2';
            g_astFeedCfg[2].iDir := -1;     g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7_rot';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 250.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7_rot';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1250.0;  g_astFeedCfg[7].stWorld.rDy := 1000.0;
            g_astFeedCfg[7].stWorld.rRot := 15.0;   (* Outfeed skew [deg] *)
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8_pal';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 250.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8_pal';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 3750.0;  g_astFeedCfg[8].stWorld.rDy := -1000.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_a';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#12;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;  g_astCamCfg[1].astMap[2].iFeed := 2;
            FOR m_i := 1 TO 2 DO
                g_astCamCfg[1].astMap[m_i].rYmin := 0.0;
                g_astCamCfg[1].astMap[m_i].rYmax := 600.0;
                g_astCamCfg[1].astMap[m_i].rTrigDist := 300.0;
                g_astCamCfg[1].astMap[m_i].rRefSpeed := 350.0;
            END_FOR

            (* Rotated slots: rotstep 90 deg per slot, 3x3, 2 layers *)
            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray3x3_rot';
            g_astPatt[1].uiRows := UINT#3;  g_astPatt[1].uiCols := UINT#3;
            g_astPatt[1].rDx := 150.0;      g_astPatt[1].rDy := 150.0;
            g_astPatt[1].rRotStep := 90.0;      (* 90 deg per slot [deg] *)
            g_astPatt[1].pBase.rX := 200.0; g_astPatt[1].pBase.rY := 200.0;
            g_astPatt[1].uiLayers := UINT#2;    g_astPatt[1].rLayerH := 120.0;
            g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 500.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray4x4_sta';
            g_astPatt[2].uiRows := UINT#4;  g_astPatt[2].uiCols := UINT#4;
            g_astPatt[2].rDx := 110.0;      g_astPatt[2].rDy := 110.0;
            g_astPatt[2].pBase.rX := 150.0; g_astPatt[2].pBase.rY := 150.0;
            g_astPatt[2].uiLayers := UINT#1;    g_astPatt[2].rZBase := 950.0;
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_rot7';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#5;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#4;
            g_astBatchDef[1].udiQty := UDINT#54;    (* 9 slots x 2 layers x 3 trays *)
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 10;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_pal8';
            g_astBatchDef[2].iOutFeed := 8; g_astBatchDef[2].uiPattId := UINT#2;
            g_astBatchDef[2].aiMix[1] := UINT#3;    g_astBatchDef[2].aiMixCnt[1] := UINT#8;
            g_astBatchDef[2].aiMix[2] := UINT#4;    g_astBatchDef[2].aiMixCnt[2] := UINT#8;
            g_astBatchDef[2].udiQty := UDINT#48;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[2].iPriority := 5;

            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: reverse belts + rotated trays, place on 7 ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Fw.g_abPlaceTrack[7] := TRUE;
            GVL_SP_Hmi.sRecipeName := 'cfg6_rotrev';
            sMsg := 'CFG6 rotrev: reverse belts, 90deg slots, 2 layers';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 7 - onecam4feed (STRANGE): ONE camera watches FOUR infeeds with
   four DIFFERENT regions (ymin/ymax) and per-feed trigger distances and
   reference speeds; camera 2 stays unused. Three high-mix batches on a
   single outfeed with three different trigger policies.
   ----------------------------------------------------------------------- *)
        7:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'inf_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 500.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 600.0;   g_astConvCfg[1].rSlowAhead := 200.0;
            g_astConvCfg[1].rStopAhead := 100.0; g_astConvCfg[1].rSlowFactor := 0.4;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'inf_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 600.0;  g_astFeedCfg[1].rPickAhead := 350.0;
            g_astFeedCfg[1].tTimeout := T#8s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'inf_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 400.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 600.0;   g_astConvCfg[2].rSlowAhead := 200.0;
            g_astConvCfg[2].rStopAhead := 100.0; g_astConvCfg[2].rSlowFactor := 0.4;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'inf_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 600.0;  g_astFeedCfg[2].rPickAhead := 350.0;
            g_astFeedCfg[2].tTimeout := T#8s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[3].bUsed := TRUE;  g_astConvCfg[3].sName := 'inf_3';
            g_astConvCfg[3].rEncScale := 0.1;   g_astConvCfg[3].iDir := 1;
            g_astConvCfg[3].rMaxSpeed := 300.0; g_astConvCfg[3].rWinStart := 300.0;
            g_astConvCfg[3].rWinLen := 600.0;   g_astConvCfg[3].rSlowAhead := 200.0;
            g_astConvCfg[3].rStopAhead := 100.0; g_astConvCfg[3].rSlowFactor := 0.4;
            g_astConvCfg[3].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[3].bUsed := TRUE;  g_astFeedCfg[3].sName := 'inf_3';
            g_astFeedCfg[3].iDir := 1;      g_astFeedCfg[3].rWinStart := 300.0;
            g_astFeedCfg[3].rWinLen := 600.0;  g_astFeedCfg[3].rPickAhead := 350.0;
            g_astFeedCfg[3].tTimeout := T#8s;  g_astFeedCfg[3].rZBelt := 850.0;
            g_astFeedCfg[3].stWorld.rDy := -500.0;
            g_astFeedCfg[3].stWorld.rScale := 1.0;
            g_astFeedCfg[3].stWorld.bValid := TRUE;

            g_astConvCfg[4].bUsed := TRUE;  g_astConvCfg[4].sName := 'inf_4';
            g_astConvCfg[4].rEncScale := 0.1;   g_astConvCfg[4].iDir := 1;
            g_astConvCfg[4].rMaxSpeed := 200.0; g_astConvCfg[4].rWinStart := 300.0;
            g_astConvCfg[4].rWinLen := 600.0;   g_astConvCfg[4].rSlowAhead := 200.0;
            g_astConvCfg[4].rStopAhead := 100.0; g_astConvCfg[4].rSlowFactor := 0.4;
            g_astConvCfg[4].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[4].bUsed := TRUE;  g_astFeedCfg[4].sName := 'inf_4';
            g_astFeedCfg[4].iDir := 1;      g_astFeedCfg[4].rWinStart := 300.0;
            g_astFeedCfg[4].rWinLen := 600.0;  g_astFeedCfg[4].rPickAhead := 350.0;
            g_astFeedCfg[4].tTimeout := T#8s;  g_astFeedCfg[4].rZBelt := 850.0;
            g_astFeedCfg[4].stWorld.rDx := 2500.0;
            g_astFeedCfg[4].stWorld.rScale := 1.0;
            g_astFeedCfg[4].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 300.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1250.0;  g_astFeedCfg[7].stWorld.rDy := 1000.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            (* ONE camera, FOUR different feed regions *)
            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_multi';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#16;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;
            g_astCamCfg[1].astMap[1].rYmin := 0.0;  g_astCamCfg[1].astMap[1].rYmax := 150.0;
            g_astCamCfg[1].astMap[1].rTrigDist := 250.0;
            g_astCamCfg[1].astMap[1].rRefSpeed := 500.0;
            g_astCamCfg[1].astMap[2].iFeed := 2;
            g_astCamCfg[1].astMap[2].rYmin := 150.0; g_astCamCfg[1].astMap[2].rYmax := 300.0;
            g_astCamCfg[1].astMap[2].rTrigDist := 300.0;
            g_astCamCfg[1].astMap[2].rRefSpeed := 400.0;
            g_astCamCfg[1].astMap[3].iFeed := 3;
            g_astCamCfg[1].astMap[3].rYmin := 300.0; g_astCamCfg[1].astMap[3].rYmax := 450.0;
            g_astCamCfg[1].astMap[3].rTrigDist := 350.0;
            g_astCamCfg[1].astMap[3].rRefSpeed := 300.0;
            g_astCamCfg[1].astMap[4].iFeed := 4;
            g_astCamCfg[1].astMap[4].rYmin := 450.0; g_astCamCfg[1].astMap[4].rYmax := 600.0;
            g_astCamCfg[1].astMap[4].rTrigDist := 400.0;
            g_astCamCfg[1].astMap[4].rRefSpeed := 200.0;
            (* Camera 2 stays unused: cleared by the common wipe *)

            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;

            (* Three high-mix batches, three trigger policies *)
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_3mix';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#1;
            g_astBatchDef[1].aiMix[1] := UINT#1;    g_astBatchDef[1].aiMixCnt[1] := UINT#4;
            g_astBatchDef[1].aiMix[2] := UINT#2;    g_astBatchDef[1].aiMixCnt[2] := UINT#4;
            g_astBatchDef[1].aiMix[3] := UINT#3;    g_astBatchDef[1].aiMixCnt[3] := UINT#4;
            g_astBatchDef[1].udiQty := UDINT#36;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[1].iPriority := 20;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_2mix';
            g_astBatchDef[2].iOutFeed := 7; g_astBatchDef[2].uiPattId := UINT#1;
            g_astBatchDef[2].aiMix[1] := UINT#4;    g_astBatchDef[2].aiMixCnt[1] := UINT#3;
            g_astBatchDef[2].aiMix[2] := UINT#5;    g_astBatchDef[2].aiMixCnt[2] := UINT#3;
            g_astBatchDef[2].udiQty := UDINT#24;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#Sensor;
            g_astBatchDef[2].iPriority := 30;
            g_astBatchDef[3].bUsed := TRUE; g_astBatchDef[3].sName := 'b3_3mix';
            g_astBatchDef[3].iOutFeed := 7; g_astBatchDef[3].uiPattId := UINT#1;
            g_astBatchDef[3].aiMix[1] := UINT#6;    g_astBatchDef[3].aiMixCnt[1] := UINT#2;
            g_astBatchDef[3].aiMix[2] := UINT#7;    g_astBatchDef[3].aiMixCnt[2] := UINT#2;
            g_astBatchDef[3].aiMix[3] := UINT#8;    g_astBatchDef[3].aiMixCnt[3] := UINT#2;
            g_astBatchDef[3].udiQty := UDINT#12;
            g_astBatchDef[3].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[3].iPriority := 10;

            FOR m_i := 1 TO 4 DO
                g_stShareCfg.aiOutfeedMap[m_i] := 7;
            END_FOR
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
            END_FOR
            FOR m_k := 2 TO 3 DO
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
            END_FOR
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[3][m_k] := 600.0;
            END_FOR
            FOR m_k := 3 TO 4 DO
                g_stShareCfg.arRangeTo[4][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: flying pick, static place ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Hmi.sRecipeName := 'cfg7_1cam4feed';
            sMsg := 'CFG7 onecam4feed: 1 cam, 4 regions, 3 mixed batches';
            bDone := TRUE;

(* -----------------------------------------------------------------------
   CONFIG 8 - stress (STRANGE): kitchen-sink stress matrix. Mixed speeds
   200..1200 user units/s, tight tracking windows, zone interlock ON with
   the classic two-zone map, ADVANCED collision prevention ON (speed
   limits + TCP separation), inverted batch priorities, all three trigger
   policies at once, belt-to-belt on both outfeeds.
   ----------------------------------------------------------------------- *)
        8:
            g_astConvCfg[1].bUsed := TRUE;  g_astConvCfg[1].sName := 'fast_1';
            g_astConvCfg[1].rEncScale := 0.1;   g_astConvCfg[1].iDir := 1;
            g_astConvCfg[1].rMaxSpeed := 1200.0; g_astConvCfg[1].rWinStart := 300.0;
            g_astConvCfg[1].rWinLen := 350.0;   g_astConvCfg[1].rSlowAhead := 150.0;
            g_astConvCfg[1].rStopAhead := 80.0; g_astConvCfg[1].rSlowFactor := 0.3;
            g_astConvCfg[1].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[1].bUsed := TRUE;  g_astFeedCfg[1].sName := 'fast_1';
            g_astFeedCfg[1].iDir := 1;      g_astFeedCfg[1].rWinStart := 300.0;
            g_astFeedCfg[1].rWinLen := 350.0;  g_astFeedCfg[1].rPickAhead := 200.0;
            g_astFeedCfg[1].tTimeout := T#5s;  g_astFeedCfg[1].rZBelt := 850.0;
            g_astFeedCfg[1].stWorld.rScale := 1.0;
            g_astFeedCfg[1].stWorld.bValid := TRUE;

            g_astConvCfg[2].bUsed := TRUE;  g_astConvCfg[2].sName := 'slow_2';
            g_astConvCfg[2].rEncScale := 0.1;   g_astConvCfg[2].iDir := 1;
            g_astConvCfg[2].rMaxSpeed := 200.0; g_astConvCfg[2].rWinStart := 300.0;
            g_astConvCfg[2].rWinLen := 350.0;   g_astConvCfg[2].rSlowAhead := 150.0;
            g_astConvCfg[2].rStopAhead := 80.0; g_astConvCfg[2].rSlowFactor := 0.3;
            g_astConvCfg[2].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[2].bUsed := TRUE;  g_astFeedCfg[2].sName := 'slow_2';
            g_astFeedCfg[2].iDir := 1;      g_astFeedCfg[2].rWinStart := 300.0;
            g_astFeedCfg[2].rWinLen := 350.0;  g_astFeedCfg[2].rPickAhead := 200.0;
            g_astFeedCfg[2].tTimeout := T#5s;  g_astFeedCfg[2].rZBelt := 850.0;
            g_astFeedCfg[2].stWorld.rDy := 600.0;
            g_astFeedCfg[2].stWorld.rScale := 1.0;
            g_astFeedCfg[2].stWorld.bValid := TRUE;

            g_astConvCfg[3].bUsed := TRUE;  g_astConvCfg[3].sName := 'mid_3';
            g_astConvCfg[3].rEncScale := 0.1;   g_astConvCfg[3].iDir := -1;
            g_astConvCfg[3].rMaxSpeed := 800.0; g_astConvCfg[3].rWinStart := 300.0;
            g_astConvCfg[3].rWinLen := 350.0;   g_astConvCfg[3].rSlowAhead := 150.0;
            g_astConvCfg[3].rStopAhead := 80.0; g_astConvCfg[3].rSlowFactor := 0.3;
            g_astConvCfg[3].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[3].bUsed := TRUE;  g_astFeedCfg[3].sName := 'mid_3';
            g_astFeedCfg[3].iDir := -1;     g_astFeedCfg[3].rWinStart := 300.0;
            g_astFeedCfg[3].rWinLen := 350.0;  g_astFeedCfg[3].rPickAhead := 200.0;
            g_astFeedCfg[3].tTimeout := T#5s;  g_astFeedCfg[3].rZBelt := 850.0;
            g_astFeedCfg[3].stWorld.rDy := -500.0;
            g_astFeedCfg[3].stWorld.rScale := 1.0;
            g_astFeedCfg[3].stWorld.bValid := TRUE;

            g_astConvCfg[4].bUsed := TRUE;  g_astConvCfg[4].sName := 'fast_4';
            g_astConvCfg[4].rEncScale := 0.1;   g_astConvCfg[4].iDir := 1;
            g_astConvCfg[4].rMaxSpeed := 1000.0; g_astConvCfg[4].rWinStart := 300.0;
            g_astConvCfg[4].rWinLen := 350.0;   g_astConvCfg[4].rSlowAhead := 150.0;
            g_astConvCfg[4].rStopAhead := 80.0; g_astConvCfg[4].rSlowFactor := 0.3;
            g_astConvCfg[4].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[4].bUsed := TRUE;  g_astFeedCfg[4].sName := 'fast_4';
            g_astFeedCfg[4].iDir := 1;      g_astFeedCfg[4].rWinStart := 300.0;
            g_astFeedCfg[4].rWinLen := 350.0;  g_astFeedCfg[4].rPickAhead := 200.0;
            g_astFeedCfg[4].tTimeout := T#5s;  g_astFeedCfg[4].rZBelt := 850.0;
            g_astFeedCfg[4].stWorld.rDx := 2500.0;
            g_astFeedCfg[4].stWorld.rScale := 1.0;
            g_astFeedCfg[4].stWorld.bValid := TRUE;

            g_astConvCfg[5].bUsed := TRUE;  g_astConvCfg[5].sName := 'mid_5';
            g_astConvCfg[5].rEncScale := 0.1;   g_astConvCfg[5].iDir := 1;
            g_astConvCfg[5].rMaxSpeed := 600.0; g_astConvCfg[5].rWinStart := 300.0;
            g_astConvCfg[5].rWinLen := 350.0;   g_astConvCfg[5].rSlowAhead := 150.0;
            g_astConvCfg[5].rStopAhead := 80.0; g_astConvCfg[5].rSlowFactor := 0.3;
            g_astConvCfg[5].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[5].bUsed := TRUE;  g_astFeedCfg[5].sName := 'mid_5';
            g_astFeedCfg[5].iDir := 1;      g_astFeedCfg[5].rWinStart := 300.0;
            g_astFeedCfg[5].rWinLen := 350.0;  g_astFeedCfg[5].rPickAhead := 200.0;
            g_astFeedCfg[5].tTimeout := T#5s;  g_astFeedCfg[5].rZBelt := 850.0;
            g_astFeedCfg[5].stWorld.rDx := 2500.0;  g_astFeedCfg[5].stWorld.rDy := 500.0;
            g_astFeedCfg[5].stWorld.rScale := 1.0;
            g_astFeedCfg[5].stWorld.bValid := TRUE;

            g_astConvCfg[6].bUsed := TRUE;  g_astConvCfg[6].sName := 'slow_6';
            g_astConvCfg[6].rEncScale := 0.1;   g_astConvCfg[6].iDir := 1;
            g_astConvCfg[6].rMaxSpeed := 200.0; g_astConvCfg[6].rWinStart := 300.0;
            g_astConvCfg[6].rWinLen := 350.0;   g_astConvCfg[6].rSlowAhead := 150.0;
            g_astConvCfg[6].rStopAhead := 80.0; g_astConvCfg[6].rSlowFactor := 0.3;
            g_astConvCfg[6].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[6].bUsed := TRUE;  g_astFeedCfg[6].sName := 'slow_6';
            g_astFeedCfg[6].iDir := 1;      g_astFeedCfg[6].rWinStart := 300.0;
            g_astFeedCfg[6].rWinLen := 350.0;  g_astFeedCfg[6].rPickAhead := 200.0;
            g_astFeedCfg[6].tTimeout := T#5s;  g_astFeedCfg[6].rZBelt := 850.0;
            g_astFeedCfg[6].stWorld.rDx := 2500.0;  g_astFeedCfg[6].stWorld.rDy := -500.0;
            g_astFeedCfg[6].stWorld.rScale := 1.0;
            g_astFeedCfg[6].stWorld.bValid := TRUE;

            g_astConvCfg[7].bUsed := TRUE;  g_astConvCfg[7].sName := 'out_7_trk';
            g_astConvCfg[7].rEncScale := 0.1;   g_astConvCfg[7].iDir := 1;
            g_astConvCfg[7].rMaxSpeed := 400.0; g_astConvCfg[7].rWinStart := 300.0;
            g_astConvCfg[7].rWinLen := 600.0;   g_astConvCfg[7].rSlowAhead := 200.0;
            g_astConvCfg[7].rStopAhead := 100.0; g_astConvCfg[7].rSlowFactor := 0.5;
            g_astConvCfg[7].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[7].bUsed := TRUE;  g_astFeedCfg[7].sName := 'out_7_trk';
            g_astFeedCfg[7].iDir := 1;      g_astFeedCfg[7].rWinStart := 300.0;
            g_astFeedCfg[7].rWinLen := 600.0;  g_astFeedCfg[7].rPickAhead := 450.0;
            g_astFeedCfg[7].tTimeout := T#30s; g_astFeedCfg[7].rZBelt := 900.0;
            g_astFeedCfg[7].stWorld.rDx := 1100.0;  g_astFeedCfg[7].stWorld.rDy := -500.0;
            g_astFeedCfg[7].stWorld.rScale := 1.0;
            g_astFeedCfg[7].stWorld.bValid := TRUE;

            g_astConvCfg[8].bUsed := TRUE;  g_astConvCfg[8].sName := 'out_8_trk';
            g_astConvCfg[8].rEncScale := 0.1;   g_astConvCfg[8].iDir := 1;
            g_astConvCfg[8].rMaxSpeed := 400.0; g_astConvCfg[8].rWinStart := 300.0;
            g_astConvCfg[8].rWinLen := 600.0;   g_astConvCfg[8].rSlowAhead := 200.0;
            g_astConvCfg[8].rStopAhead := 100.0; g_astConvCfg[8].rSlowFactor := 0.5;
            g_astConvCfg[8].eDrive := ET_SP_ConvDriveMode#ServoAxis;
            g_astFeedCfg[8].bUsed := TRUE;  g_astFeedCfg[8].sName := 'out_8_trk';
            g_astFeedCfg[8].iDir := 1;      g_astFeedCfg[8].rWinStart := 300.0;
            g_astFeedCfg[8].rWinLen := 600.0;  g_astFeedCfg[8].rPickAhead := 450.0;
            g_astFeedCfg[8].tTimeout := T#30s; g_astFeedCfg[8].rZBelt := 900.0;
            g_astFeedCfg[8].stWorld.rDx := 1100.0;  g_astFeedCfg[8].stWorld.rDy := 1100.0;
            g_astFeedCfg[8].stWorld.rScale := 1.0;
            g_astFeedCfg[8].stWorld.bValid := TRUE;

            FOR m_i := 1 TO GC_FEEDS DO
                IF g_astFeedCfg[m_i].bUsed THEN
                    FOR m_k := 1 TO GC_CAMS DO
                        g_astFeedCfg[m_i].astCalib[m_k].rScale := 1.0;
                        g_astFeedCfg[m_i].astCalib[m_k].bValid := TRUE;
                    END_FOR
                END_IF
            END_FOR

            g_astCamCfg[1].bUsed := TRUE;   g_astCamCfg[1].sName := 'cam_a';
            g_astCamCfg[1].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[1].sIp := '127.0.0.1';  g_astCamCfg[1].uiPort := UINT#0;
            g_astCamCfg[1].tTimeout := T#800ms; g_astCamCfg[1].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[1].uiMaxItems := UINT#16;   g_astCamCfg[1].bThInRad := FALSE;
            g_astCamCfg[1].rMinScore := 0.8;
            g_astCamCfg[1].astMap[1].iFeed := 1;  g_astCamCfg[1].astMap[2].iFeed := 2;
            g_astCamCfg[1].astMap[3].iFeed := 3;
            FOR m_i := 1 TO 3 DO
                g_astCamCfg[1].astMap[m_i].rYmin := 0.0;
                g_astCamCfg[1].astMap[m_i].rYmax := 600.0;
                g_astCamCfg[1].astMap[m_i].rTrigDist := 250.0;
                g_astCamCfg[1].astMap[m_i].rRefSpeed := 600.0;
            END_FOR
            g_astCamCfg[2].bUsed := TRUE;   g_astCamCfg[2].sName := 'cam_b';
            g_astCamCfg[2].eDrv := ET_SP_CamDrv#Simulated;
            g_astCamCfg[2].sIp := '127.0.0.1';  g_astCamCfg[2].uiPort := UINT#0;
            g_astCamCfg[2].tTimeout := T#800ms; g_astCamCfg[2].eTrig := ET_SP_TrigMode#Distance;
            g_astCamCfg[2].uiMaxItems := UINT#16;   g_astCamCfg[2].bThInRad := FALSE;
            g_astCamCfg[2].rMinScore := 0.8;
            g_astCamCfg[2].astMap[1].iFeed := 4;  g_astCamCfg[2].astMap[2].iFeed := 5;
            g_astCamCfg[2].astMap[3].iFeed := 6;
            FOR m_i := 1 TO 3 DO
                g_astCamCfg[2].astMap[m_i].rYmin := 0.0;
                g_astCamCfg[2].astMap[m_i].rYmax := 600.0;
                g_astCamCfg[2].astMap[m_i].rTrigDist := 250.0;
                g_astCamCfg[2].astMap[m_i].rRefSpeed := 600.0;
            END_FOR

            g_astPatt[1].bUsed := TRUE;     g_astPatt[1].sName := 'tray4x4';
            g_astPatt[1].uiRows := UINT#4;  g_astPatt[1].uiCols := UINT#4;
            g_astPatt[1].rDx := 110.0;      g_astPatt[1].rDy := 110.0;
            g_astPatt[1].pBase.rX := 150.0; g_astPatt[1].pBase.rY := 150.0;
            g_astPatt[1].uiLayers := UINT#1;    g_astPatt[1].rZBase := 950.0;
            g_astPatt[1].rTrigDist := 450.0;
            g_astPatt[2].bUsed := TRUE;     g_astPatt[2].sName := 'tray5x3';
            g_astPatt[2].uiRows := UINT#5;  g_astPatt[2].uiCols := UINT#3;
            g_astPatt[2].rDx := 120.0;      g_astPatt[2].rDy := 120.0;
            g_astPatt[2].pBase.rX := 160.0; g_astPatt[2].pBase.rY := 160.0;
            g_astPatt[2].uiLayers := UINT#1;    g_astPatt[2].rZBase := 950.0;
            g_astPatt[2].rTrigDist := 500.0;

            (* Inverted priorities: small batches run first *)
            g_astBatchDef[1].bUsed := TRUE; g_astBatchDef[1].sName := 'b1_small';
            g_astBatchDef[1].iOutFeed := 7; g_astBatchDef[1].uiPattId := UINT#2;
            g_astBatchDef[1].aiMix[1] := UINT#9;    g_astBatchDef[1].aiMixCnt[1] := UINT#5;
            g_astBatchDef[1].udiQty := UDINT#15;
            g_astBatchDef[1].eTrig := ET_SP_PattTrig#Sensor;
            g_astBatchDef[1].iPriority := 100;
            g_astBatchDef[2].bUsed := TRUE; g_astBatchDef[2].sName := 'b2_flood';
            g_astBatchDef[2].iOutFeed := 7; g_astBatchDef[2].uiPattId := UINT#1;
            g_astBatchDef[2].aiMix[1] := UINT#1;    g_astBatchDef[2].aiMixCnt[1] := UINT#8;
            g_astBatchDef[2].aiMix[2] := UINT#2;    g_astBatchDef[2].aiMixCnt[2] := UINT#8;
            g_astBatchDef[2].udiQty := UDINT#64;
            g_astBatchDef[2].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[2].iPriority := 1;
            g_astBatchDef[3].bUsed := TRUE; g_astBatchDef[3].sName := 'b3_small';
            g_astBatchDef[3].iOutFeed := 8; g_astBatchDef[3].uiPattId := UINT#2;
            g_astBatchDef[3].aiMix[1] := UINT#3;    g_astBatchDef[3].aiMixCnt[1] := UINT#5;
            g_astBatchDef[3].udiQty := UDINT#15;
            g_astBatchDef[3].eTrig := ET_SP_PattTrig#BatchStart;
            g_astBatchDef[3].iPriority := 100;
            g_astBatchDef[4].bUsed := TRUE; g_astBatchDef[4].sName := 'b4_flood';
            g_astBatchDef[4].iOutFeed := 8; g_astBatchDef[4].uiPattId := UINT#1;
            g_astBatchDef[4].aiMix[1] := UINT#4;    g_astBatchDef[4].aiMixCnt[1] := UINT#8;
            g_astBatchDef[4].aiMix[2] := UINT#5;    g_astBatchDef[4].aiMixCnt[2] := UINT#8;
            g_astBatchDef[4].udiQty := UDINT#64;
            g_astBatchDef[4].eTrig := ET_SP_PattTrig#Distance;
            g_astBatchDef[4].iPriority := 1;

            (* Zones: feeds 1..3 = zone 1, feeds 4..6 = zone 2 *)
            g_aiFeedZone[1] := 1;   g_aiFeedZone[2] := 1;   g_aiFeedZone[3] := 1;
            g_aiFeedZone[4] := 2;   g_aiFeedZone[5] := 2;   g_aiFeedZone[6] := 2;
            g_stSysCfg.bZoneGuard := TRUE;      (* Legacy zone interlock    *)
            g_stSysCfg.bColAdv := TRUE;         (* R-05b superset replaces it *)
            g_stSysCfg.bResilience := TRUE;     (* Continue on robot loss   *)
            g_stSysCfg.bStopConvsOnPause := TRUE;

            (* Weighted shares + strict order + pick bias *)
            g_stShareCfg.arRatio[1] := 2.0;
            g_stShareCfg.bStrictOrder := TRUE;
            g_stShareCfg.rPickBias := 0.7;
            g_stShareCfg.aiOutfeedMap[1] := 7;  g_stShareCfg.aiOutfeedMap[2] := 7;
            g_stShareCfg.aiOutfeedMap[3] := 7;  g_stShareCfg.aiOutfeedMap[4] := 8;
            g_stShareCfg.aiOutfeedMap[5] := 8;  g_stShareCfg.aiOutfeedMap[6] := 8;
            FOR m_k := 1 TO 2 DO
                g_stShareCfg.arRangeTo[1][m_k] := 600.0;
                g_stShareCfg.arRangeTo[2][m_k] := 600.0;
                g_stShareCfg.arRangeTo[3][m_k] := 600.0;
            END_FOR
            FOR m_k := 3 TO 4 DO
                g_stShareCfg.arRangeTo[4][m_k] := 600.0;
                g_stShareCfg.arRangeTo[5][m_k] := 600.0;
                g_stShareCfg.arRangeTo[6][m_k] := 600.0;
            END_FOR

            (* ---- Tracking: full belt-to-belt + stress guards ---- *)
            GVL_SP_Fw.g_eTrkMode := 1;
            GVL_SP_Fw.g_abPlaceTrack[7] := TRUE;
            GVL_SP_Fw.g_abPlaceTrack[8] := TRUE;
            GVL_SP_Hmi.sRecipeName := 'cfg8_stress';
            sMsg := 'CFG8 stress: 200-1200 spd, zones+collision, prio inv';
            bDone := TRUE;

    END_CASE

    (* ====================================================================
       4) PUBLISH: PRG_SP_TaskMain + PRG_SP_TaskFast re-apply everything to the FBs.
       ==================================================================== *)
    IF bDone THEN
        iLastCfg := m_iSel;             (* Diagnostic: last applied id *)
        GVL_SP_Hmi.bApplyConfig := TRUE;(* Main section 2: Configure() all *)
    END_IF
END_IF
END_PROGRAM
