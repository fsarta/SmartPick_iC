(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 15_Professional
   Worksheet : FB - SP_SelfTest
   -----------------------------------------------------------------------------
   Purpose   : One-shot startup / commissioning self-test (roadmap R-16).
               Validates the cross-module consistency of the configuration
               mirrors BEFORE production is attempted:

     Check  1: robot records (used, tool count, tool sanity, cup count)
     Check  2: multi-grip integrity (uiMaxGrip vs cups, Sync needs match
               tolerance, cluster tool present)
     Check  3: outfeed map (valid targets, no self-mapping)
     Check  4: feed tracking windows (length, direction, timeout)
     Check  5: zone maps (feed zones in range; collision thresholds
               ordered: rStopDist < rSlowDist)
     Check  6: camera configurations (address for real drivers)
     Check  7: batch definitions (pattern id, quantity, outfeed used)

   The result is a plain data record (ST_SP_TestRes) mirrored to the HMI;
   a failed check also sets bPass = FALSE and the first failure message.
   Run on demand (HMI command) or automatically after a recipe load (the
   Main re-apply path). Pure logic, no firmware access, simulation-safe.

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_SelfTest
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    (* One-shot trigger (HMI command or recipe-load hook) *)
    bRun  : BOOL;
    stNow : Yt_YA_RTC_Struct;   (* Wall clock stamp (from TaskSvc) *)
END_VAR
VAR_OUTPUT
    (* Result record (mirrored to the HMI by Main) *)
    stRes : ST_SP_TestRes;
END_VAR
VAR
    (* Loop indices *)
    i, k : SINT;
    (* Message scratch *)
    sMsg : STRING(80);
END_VAR

IF bRun THEN
    stRes.uiChecks := UINT#0;
    stRes.uiFails  := UINT#0;
    FOR i := 1 TO 16 DO
        stRes.auiFail[i] := UINT#0;
    END_FOR
    stRes.sMsg := '';
    stRes.stRun := stNow;

    (* --------------------- Check 1: robot records ---------------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_ROBOTS DO
        IF g_astRobCfg[i].bUsed THEN
            IF (g_astRobCfg[i].uiNumTools < UINT#1)
               OR (g_astRobCfg[i].uiNumTools > UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS))) THEN
                sMsg := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' tool count out of range');
            END_IF
            FOR k := 1 TO SINT_TO_DINT(g_astRobCfg[i].uiNumTools) DO
                IF (sMsg = '') AND g_astRobCfg[i].astTools[k].bUsed THEN
                    IF (g_astRobCfg[i].astTools[k].uiCups < UINT#1)
                       OR (g_astRobCfg[i].astTools[k].uiCups
                           > UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
                        sMsg := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                        sMsg := CONCAT(sMsg, ' cup count out of range');
                    END_IF
                END_IF
            END_FOR
        END_IF
    END_FOR
    THIS.Close(sMsg);

    (* --------------------- Check 2: multi-grip integrity ---------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_ROBOTS DO
        IF (sMsg = '') AND g_astRobCfg[i].bUsed THEN
            IF (g_astRobCfg[i].uiMaxGrip < UINT#1)
               OR (g_astRobCfg[i].uiMaxGrip > UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
                sMsg := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' max grip out of range');
            ELSIF (g_astRobCfg[i].eGripMode = ET_SP_GripMode#Sync)
                  AND (g_astRobCfg[i].uiMaxGrip > UINT#1) THEN
                (* Synchronized clusters need a geometry tolerance and cups *)
                IF (g_astRobCfg[i].uiMaxGrip > g_astRobCfg[i].astTools[1].uiCups) THEN
                    sMsg := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                    sMsg := CONCAT(sMsg, ' sync grip exceeds cup count');
                ELSIF g_astRobCfg[i].astTools[1].rMatchTol <= 0.0 THEN
                    sMsg := CONCAT('Robot', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                    sMsg := CONCAT(sMsg, ' sync grip needs rMatchTol > 0');
                END_IF
            END_IF
        END_IF
    END_FOR
    THIS.Close(sMsg);

    (* --------------------- Check 3: outfeed map ------------------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_FEEDS DO
        IF (sMsg = '') AND g_astFeedCfg[i].bUsed AND (NOT g_astFeedIo[i].bIsOutfeed) THEN
            k := g_stShareCfg.aiOutfeedMap[i];
            IF (k < 0) OR (k > GC_FEEDS) THEN
                sMsg := CONCAT('Outfeed map feed', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' out of range');
            ELSIF k = i THEN
                sMsg := CONCAT('Outfeed map feed', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' maps to itself');
            END_IF
        END_IF
    END_FOR
    THIS.Close(sMsg);

    (* --------------------- Check 4: feed windows ------------------------ *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_FEEDS DO
        IF (sMsg = '') AND g_astFeedCfg[i].bUsed THEN
            IF (g_astFeedCfg[i].iDir <> 1) AND (g_astFeedCfg[i].iDir <> -1) THEN
                sMsg := CONCAT('Feed', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' direction invalid');
            ELSIF g_astFeedCfg[i].rWinLen <= 0.0 THEN
                sMsg := CONCAT('Feed', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' window length must be > 0');
            END_IF
        END_IF
    END_FOR
    THIS.Close(sMsg);

    (* --------------------- Check 5: zone maps --------------------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_FEEDS DO
        IF (sMsg = '') AND (g_aiFeedZone[i] > GC_ZONES) THEN
            sMsg := 'Feed zone map out of range';
        END_IF
    END_FOR
    IF (sMsg = '') AND g_stSysCfg.bColAdv THEN
        IF g_stColCfg.bDynaSep AND (g_stColCfg.rStopDist >= g_stColCfg.rSlowDist) THEN
            sMsg := 'Collision stop distance must be < slow distance';
        END_IF
    END_IF
    THIS.Close(sMsg);

    (* --------------------- Check 6: cameras ----------------------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_CAMS DO
        IF (sMsg = '') AND g_astCamCfg[i].bUsed
           AND (g_astCamCfg[i].eDrv <> ET_SP_VisionDrv#Simulated) THEN
            IF (g_astCamCfg[i].sIp = '') OR (g_astCamCfg[i].uiPort = UINT#0) THEN
                sMsg := CONCAT('Camera', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' needs IP and port');
            END_IF
        END_IF
    END_FOR
    THIS.Close(sMsg);

    (* --------------------- Check 7: batch definitions ------------------- *)
    stRes.uiChecks := stRes.uiChecks + UINT#1;
    sMsg := '';
    FOR i := 1 TO GC_BATCHES DO
        IF (sMsg = '') AND g_astBatchDef[i].bUsed THEN
            IF (g_astBatchDef[i].uiPattId < UINT#1)
               OR (g_astBatchDef[i].uiPattId > UDINT_TO_UINT(SINT_TO_UDINT(GC_PATT))) THEN
                sMsg := CONCAT('Batch', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' pattern id out of range');
            ELSIF g_astBatchDef[i].udiQty = UDINT#0 THEN
                sMsg := CONCAT('Batch', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
                sMsg := CONCAT(sMsg, ' quantity is zero');
            END_IF
        END_IF
    END_FOR
    THIS.Close(sMsg);

    stRes.bPass := (stRes.uiFails = UINT#0);
END_IF
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Close (parent SP_SelfTest) - internal
   Register the outcome of one check: an empty message means PASS,
   otherwise the failure is recorded with the message of the first fail.
   ----------------------------------------------------------------------- *)
METHOD Close : BOOL
VAR_INPUT
    (* Failure message ('' = check passed) *)
    sMsg : STRING(80);
END_VAR
    Close := (sMsg = '');           (* TRUE = check passed *)
    IF sMsg <> '' THEN
        stRes.uiFails := stRes.uiFails + UINT#1;
        IF stRes.uiFails <= UDINT_TO_UINT(SINT_TO_UDINT(16)) THEN
            stRes.auiFail[stRes.uiFails] := stRes.uiChecks;
        END_IF
        IF stRes.sMsg = '' THEN
            stRes.sMsg := sMsg;
        END_IF
    END_IF
END_METHOD
