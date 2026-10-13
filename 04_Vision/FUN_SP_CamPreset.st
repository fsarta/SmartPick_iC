(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FUN - SP_CamPreset
   -----------------------------------------------------------------------------
   Purpose   : Roadmap HW-4: per-model-family commissioning presets for the
               camera configuration. Applies field defaults to an
               ST_SP_VisionCfg for every field that is still at its neutral
               value (port 0, timeout 0, trigger mode 0 ...), leaving
               explicitly configured values untouched. The driver FBs
               (SP_DrvCognex / SP_DrvKeyence / SP_DrvGeneric) apply the
               PROTOCOL presets afterwards (trigger string, token indexes),
               so the two layers compose: model preset -> driver preset.

   Usage (PRG_SP_TaskFast configuration block, production stopped):
     IF g_aiCamModel[1] > 0 THEN
         g_astCamCfg[1] := FUN_SP_CamPreset(g_astCamCfg[1], g_aiCamModel[1]);
     END_IF
   The selector g_aiCamModel[x] uses the ET_SP_VisionDrv numbering
   (0 = keep current, 1 = Keyence, 2 = GenericTCP, 3 = Simulated) - the
   Cognex preset is selected with the Cognex driver value 0, hence the
   "keep current" slot is the value -1 when a Cognex preset is wanted:

     g_aiCamModel[x] = -1 : apply the Cognex preset (eDrv stays 0)
     g_aiCamModel[x] =  0 : keep the current configuration (no preset)
     g_aiCamModel[x] =  1 : Keyence preset
     g_aiCamModel[x] =  2 : GenericTCP preset
     g_aiCamModel[x] =  3 : Simulated preset

   Port defaults: Cognex In-Sight ASCII job 5000, Keyence ASCII 8888 -
   adapt to the on-site job configuration (configuration 2 of
   PRG_SP_ConfigInit uses the same).

   Constraints: pure function, no globals written, no pointers.
   =============================================================================
*)

FUNCTION FUN_SP_CamPreset : ST_SP_VisionCfg
VAR_INPUT
    stIn   : ST_SP_VisionCfg;   (* Current configuration (fill-if-empty) *)
    iModel : SINT;              (* Model selector, see header *)
END_VAR
VAR
    (* Configuration after fill-if-empty preset application *)
    stOut  : ST_SP_VisionCfg;
    (* Conveyor index used to pick the on-site default set *)
    uiCv   : UINT;
END_VAR
    stOut := stIn;

    (* ---------------- Driver + connection defaults ---------------------- *)
    IF iModel = -1 THEN
        stOut.eDrv := ET_SP_VisionDrv#Cognex;
        IF stOut.uiPort = UINT#0 THEN stOut.uiPort := UINT#5000; END_IF
    ELSIF iModel = 1 THEN
        stOut.eDrv := ET_SP_VisionDrv#Keyence;
        IF stOut.uiPort = UINT#0 THEN stOut.uiPort := UINT#8888; END_IF
    ELSIF iModel = 2 THEN
        stOut.eDrv := ET_SP_VisionDrv#GenericTCP;
        IF stOut.uiPort = UINT#0 THEN stOut.uiPort := UINT#10001; END_IF
    ELSIF iModel = 3 THEN
        stOut.eDrv := ET_SP_VisionDrv#Simulated;
    ELSE
        FUN_SP_CamPreset := stOut;      (* 0 / unknown: keep current *)
        RETURN;
    END_IF

    (* ---------------- Timing defaults ------------------------------------ *)
    IF stOut.tTimeout = T#0ms THEN stOut.tTimeout := T#800ms; END_IF
    uiCv := TIME_TO_UDINT(stOut.tDelay);
    IF uiCv = UDINT#0 THEN stOut.tDelay := T#40ms; END_IF

    (* ---------------- Trigger / parsing defaults -------------------------- *)
    (* eTrig stays at its configured value: Distance (0) is the neutral
       default for new configs, so only force it when the driver was
       switched (fill-if-empty on the previous driver slot). *)
    IF stOut.uiMaxItems = UINT#0 THEN
        stOut.uiMaxItems := UDINT_TO_UINT(SINT_TO_UDINT(GC_VIS_MAX));
    END_IF
    stOut.bThInRad := FALSE;        (* Application convention: theta in DEGREES *)
    IF stOut.rMinScore <= 0.0 THEN stOut.rMinScore := 0.5; END_IF

    (* Mark enabled: a preset application means the camera is commissioned *)
    stOut.bUsed := TRUE;

    FUN_SP_CamPreset := stOut;
END_FUNCTION
