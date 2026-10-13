(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : FUN - SP_RobCfgDefault
   -----------------------------------------------------------------------------
   Purpose   : Roadmap R-06: commissioning defaults for the robot/tool
               configuration (g_astRobCfg). A zeroed configuration is
               detected (uiNumTools = 0) and replaced by a safe generic
               cell setup, so the FIRST BOOT never fails the Configure
               validation (ErrParam) and the simulation runs out of the
               box. Explicitly commissioned values are never overwritten
               (fill-if-empty on the whole robot record).

   Default profile (per robot, generic suction tool):
     - 1 suction tool "Gripper1", 2 cups at +-30 mm, payload 500 g
     - Velocities: approach 2000 / track 1200 / place 1800 mm/s
     - Acceleration 8000 mm/s2, zones 5/25 mm, safe height 120 mm
     - Multi-grip Sync, max 2 parts/cycle, 1 retry
     - Pick verification ON (works in simulation through the feedback
       loop-back wired by PRG_SP_TaskFast; on site enable it only after the
       vacuum feedback inputs are proven - see HW_IO_Map doc)
     - Path offsets: approach +80 mm Z, depart +40 mm Z (flat, per
       feed x type; tune per product in the HMI editor)

   Usage (PRG_SP_TaskFast, one-shot configuration block, BEFORE Configure):
     g_astRobCfg[1] := FUN_SP_RobCfgDefault(g_astRobCfg[1], 1);
     ... one call per robot ...

   Constraints: pure function, no globals written, no pointers, loops only.
   =============================================================================
*)

FUNCTION FUN_SP_RobCfgDefault : ST_SP_RobCfg
VAR_INPUT
    stIn : ST_SP_RobCfg;        (* Current configuration (fill-if-empty) *)
    iRob : SINT;                (* Robot index 1..GC_ROBOTS *)
END_VAR
VAR
    (* Generic robot profile assembled (suction, speeds, retries) *)
    stOut : ST_SP_RobCfg;
    (* Feed / type / cup loop indices *)
    iF, iT, iC : SINT;
END_VAR
    (* Already commissioned: return unchanged *)
    IF (stIn.uiNumTools >= UINT#1) AND (stIn.uiNumTools <= UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS))) THEN
        FUN_SP_RobCfgDefault := stIn;
        RETURN;
    END_IF

    stOut := stIn;              (* Preserve optional pre-set fields *)

    (* ---------------- Identity / group binding -------------------------- *)
    stOut.bUsed    := TRUE;
    stOut.sName    := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(iRob))));
    stOut.uiGroup  := DINT_TO_UINT(SINT_TO_DINT(iRob));

    (* ---------------- Tool 1: generic suction gripper -------------------- *)
    stOut.uiNumTools := UINT#1;
    stOut.astTools[1].bUsed       := TRUE;
    stOut.astTools[1].sName       := 'Gripper1';
    stOut.astTools[1].bSuction    := TRUE;
    stOut.astTools[1].rMaxWeight  := 500.0;
    stOut.astTools[1].uiPickOutCh := UINT#0;    (* 0 = auto (robot-1)*4+tool *)
    stOut.astTools[1].uiPlaceOutCh:= UINT#0;
    stOut.astTools[1].uiFbkInCh   := UINT#0;
    stOut.astTools[1].tGrip       := T#150ms;
    stOut.astTools[1].tRelease    := T#100ms;
    stOut.astTools[1].rAdvance    := 40.0;      (* Cut-off margin [mm] *)
    stOut.astTools[1].uiCups      := UINT#2;
    stOut.astTools[1].bSingleType := FALSE;
    FOR iC := 1 TO GC_CUPS DO
        stOut.astTools[1].astCups[iC].rX := 0.0;
        stOut.astTools[1].astCups[iC].rY := 0.0;
        stOut.astTools[1].astCups[iC].rZ := 0.0;
    END_FOR
    stOut.astTools[1].astCups[1].rX := -30.0;   (* Cup row across the belt *)
    stOut.astTools[1].astCups[2].rX := 30.0;

    (* R-07 advanced multi-grip tool parameters (safe generic cluster) *)
    FOR iC := 1 TO GC_CUPS DO
        stOut.astTools[1].auiCupFbkCh[iC] := UINT#0;    (* 0 = tool fbk *)
    END_FOR
    stOut.astTools[1].rMatchTol := 8.0;         (* Cluster match tolerance [mm] *)
    stOut.astTools[1].rCapCog   := 0.0;         (* CoG audit off until weighed *)

    (* Tools 2..4: present but unused (safe neutral state) *)
    FOR iT := 2 TO GC_TOOLS DO
        stOut.astTools[iT].bUsed := FALSE;
        stOut.astTools[iT].sName := CONCAT('Tool', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(iT))));
        stOut.astTools[iT].uiCups := UINT#1;
        stOut.astTools[iT].tGrip := T#150ms;
        stOut.astTools[iT].tRelease := T#100ms;
        stOut.astTools[iT].rAdvance := 40.0;
    END_FOR

    (* ---------------- Motion profile -------------------------------------- *)
    stOut.rVelApp   := 2000.0;
    stOut.rVelTrack := 1200.0;
    stOut.rVelPlace := 1800.0;
    stOut.rAcc      := 8000.0;
    stOut.rDec      := 8000.0;
    stOut.ePrecApp  := ET_SP_Precision#ZoneWide;
    stOut.ePrecPick := ET_SP_Precision#Exact;
    stOut.ePrecPlace:= ET_SP_Precision#ZoneTight;
    stOut.rZoneTight:= 5.0;
    stOut.rZoneWide := 25.0;
    stOut.rZSafe    := 120.0;
    stOut.tHomeTimeout := T#30s;

    (* ---------------- Multi-grip / verification --------------------------- *)
    stOut.eGripMode    := ET_SP_GripMode#Sync;
    stOut.uiMaxGrip    := UINT#2;
    stOut.bVerifyPick  := TRUE;     (* Sim loop-back confirms; site: see doc *)
    stOut.bVerifyPlace := FALSE;
    stOut.bDeferVerify := FALSE;
    stOut.uiRetries    := UINT#1;

    (* ---------------- Camera ownership (resiliency seed) ------------------ *)
    FOR iT := 1 TO GC_CAMS DO
        stOut.abiCamOwner[iT] := (iRob = iT);   (* Robot i owns camera i *)
    END_FOR

    (* ---------------- 3-point path offsets (feed x type) ------------------ *)
    FOR iF := 1 TO GC_FEEDS DO
        FOR iT := 1 TO GC_TYPES DO
            stOut.astOff[iF][iT].rAppDx := 0.0;
            stOut.astOff[iF][iT].rAppDy := 0.0;
            stOut.astOff[iF][iT].rAppDz := 80.0;    (* Approach above point *)
            stOut.astOff[iF][iT].rDepDx := 0.0;
            stOut.astOff[iF][iT].rDepDy := 0.0;
            stOut.astOff[iF][iT].rDepDz := 40.0;    (* Depart above point *)
            stOut.astOff[iF][iT].rPtDz  := 0.0;
        END_FOR
    END_FOR

    FUN_SP_RobCfgDefault := stOut;
END_FUNCTION
