(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 10_Persistence
   Worksheet : FB - SP_RecipeMgr
   -----------------------------------------------------------------------------
   Purpose   : Recipe export/import as fixed-record CSV (one line per
               configuration object, comma separated, '.' decimals).
               The wiring program streams the lines through SP_FileIo.

   Record layout (token order is FIXED; the parser is positional):
     #SmartPick_iC Recipe v2,<name>
     CONV,<n>,<scale>,<dir>,<maxspd>,<winstart>,<winlen>,<slowahead>,<stopahead>,<slowf>,<drive>,<anach>
     FEED,<n>,<dir>,<winstart>,<winlen>,<pickahead>,<timeout_ms>,<zbelt>,<out>
     CAM,<n>,<drv>,<ip>,<port>,<trig>,<trigdist>,<refspd>,<maxitems>,<thinrad>,<minscore>,<delay_ms>
     CAMMAP,<n>,<k>,<feed>,<ymin>,<ymax>,<trigd>,<refspd>
     PATT,<n>,<rows>,<cols>,<dx>,<dy>,<rotstep>,<bx>,<by>,<bth>,<layers>,<layerh>,<zbase>,<trigdist>
     BATCH,<n>,<outfeed>,<patt>,<qty>,<trig>,<priority>
     BATCHMIX,<n>,<k>,<type>,<cnt>
     SHARE,<feed>,<strat>,<match>,<strict>,<pickbias>
     SHARER,<feed>,<robot>,<ratio>,<rangef>,<ranget>,<tmask>,<manual>

   UNITS (v1.7.0): distances in [mm], ALL angle tokens in DEGREES
   (FEED <rot>, PATT <rotstep>/<bth>). CAM <thinrad> declares the camera
   theta unit: 0 = degrees (default), 1 = radians (converted on parse).
   Files tagged 'Recipe v1' carried radians and are REJECTED on import to
   avoid silently mis-scaled rotations.

   Scope note: robot/tool commissioning data (velocities, grip times, cup
   geometry) is intentionally NOT part of the product recipe (roadmap
   item R-03 of the architecture guide).

   Targets (single writer: import runs with production stopped):
     g_astConvCfg, g_astFeedCfg, g_astCamCfg, g_astPatt,
     g_astBatchDef, g_stShareCfg
   =============================================================================
*)

FUNCTION_BLOCK SP_RecipeMgr
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    out_sLine : STRING(200);    (* Export: line to write *)
    uiProgress: UINT;           (* Export row counter (diagnostic) *)
    bErr      : BOOL;           (* Last import line rejected *)
    sName     : STRING(32);     (* Recipe name *)
END_VAR
VAR
    (* TRUE = export phase active, FALSE = import *)
    m_bExport : BOOL;
    m_iRow    : UDINT := UDINT#0;   (* Export row cursor *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Passive FB: driven by ExportNext / ImportLine through the wiring. *)
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: ExportBegin (parent SP_RecipeMgr)
   Arm the export iterator with the recipe name.
   ----------------------------------------------------------------------- *)
METHOD ExportBegin : BOOL
VAR_INPUT
    (* Recipe file name (without extension) *)
    sName : STRING(32);
END_VAR
    ExportBegin := TRUE;            (* Export iterator armed *)
    m_bExport := TRUE;
    m_iRow := UDINT#0;
    sName := sName;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExportNext (parent SP_RecipeMgr)
   Produce the next recipe line in out_sLine. FALSE when finished.
   ----------------------------------------------------------------------- *)
METHOD ExportNext : BOOL
VAR
    (* Export section cursor (conv, feed, cam, ...) *)
    iSec  : SINT;
    (* Record index inside the current section *)
    iIdx  : SINT;
    (* Sub-record index (maps, mix entries) *)
    iSub  : SINT;
    (* Reserved marker written into the header *)
    r     : UDINT;
    (* Per-section record counters (feeds, cams, patterns, batches, seq, ranges) *)
    udF, udC, udP, udB, udSeq, udR : UDINT;
    (* Emitted CAMMAP and BATCHMIX line counters *)
    udMap, udMix : UDINT;
    (* TRUE when the current record holds data (skip disabled) *)
    bEmit : BOOL;
END_VAR
    ExportNext := FALSE;
    IF NOT m_bExport THEN
        RETURN;
    END_IF

    (* Section sizes *)
    udF := INT_TO_UDINT(GC_FEEDS);
    udC := INT_TO_UDINT(GC_CAMS);
    udP := INT_TO_UDINT(GC_PATT);
    udB := INT_TO_UDINT(GC_BATCHES);
    udSeq := INT_TO_UDINT(GC_SEQ);
    udR := INT_TO_UDINT(GC_ROBOTS);
    udMap := udC * udF;
    udMix := udB * udSeq;

    (* Decode the row cursor into (section, index, sub) *)
    r := m_iRow;
    iSec := -1; iIdx := 0; iSub := 0;
    IF r = UDINT#0 THEN
        iSec := 0;
    ELSE
        r := r - UDINT#1;
        IF r < udF THEN
            iSec := 1;  iIdx := UDINT_TO_DINT(r) + 1;
        ELSE
            r := r - udF;
            IF r < udF THEN
                iSec := 2;  iIdx := UDINT_TO_DINT(r) + 1;
            ELSE
                r := r - udF;
                IF r < udC THEN
                    iSec := 3;  iIdx := UDINT_TO_DINT(r) + 1;
                ELSE
                    r := r - udC;
                    IF r < udMap THEN
                        iSec := 4;
                        iIdx := UDINT_TO_DINT(r / udF) + 1;
                        iSub := UDINT_TO_DINT(r MOD udF) + 1;
                    ELSE
                        r := r - udMap;
                        IF r < udP THEN
                            iSec := 5;  iIdx := UDINT_TO_DINT(r) + 1;
                        ELSE
                            r := r - udP;
                            IF r < udB THEN
                                iSec := 6;  iIdx := UDINT_TO_DINT(r) + 1;
                            ELSE
                                r := r - udB;
                                IF r < udMix THEN
                                    iSec := 7;
                                    iIdx := UDINT_TO_DINT(r / udSeq) + 1;
                                    iSub := UDINT_TO_DINT(r MOD udSeq) + 1;
                                ELSE
                                    r := r - udMix;
                                    IF r < udF THEN
                                        iSec := 8;  iIdx := UDINT_TO_DINT(r) + 1;
                                    ELSE
                                        r := r - udF;
                                        IF r < udF * udR THEN
                                            iSec := 9;
                                            iIdx := UDINT_TO_DINT(r / udR) + 1;
                                            iSub := UDINT_TO_DINT(r MOD udR) + 1;
                                        END_IF
                                    END_IF
                                END_IF
                            END_IF
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_IF
    END_IF

    (* Emit *)
    IF iSec < 0 THEN
        m_bExport := FALSE;
        RETURN;
    END_IF

    bEmit := TRUE;
    CASE iSec OF
        0: out_sLine := CONCAT('#SmartPick_iC Recipe v2,', sName);
        1: THIS.ExpConv(iIdx);
        2: THIS.ExpFeed(iIdx);
        3: THIS.ExpCam(iIdx);
        4: THIS.ExpCamMap(iIdx, iSub);
        5: THIS.ExpPatt(iIdx);
        6: THIS.ExpBatch(iIdx);
        7: THIS.ExpBatchMix(iIdx, iSub);
        8: THIS.ExpShare(iIdx);
        9: THIS.ExpShareR(iIdx, iSub);
        ELSE bEmit := FALSE;
    END_CASE

    IF bEmit THEN
        m_iRow := m_iRow + UDINT#1;
        uiProgress := UDINT_TO_UINT(m_iRow MOD UDINT#65536);
        ExportNext := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpConv (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpConv : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
END_VAR
VAR
    (* CONV record accumulator *)
    stC : ST_SP_ConvCfg;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpConv := TRUE;                (* CONV line built *)
    stC := g_astConvCfg[i];
    s := CONCAT('CONV,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rEncScale, 6));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(stC.iDir))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rMaxSpeed, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rWinStart, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rWinLen, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rSlowAhead, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rStopAhead, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stC.rSlowFactor, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(stC.eDrive)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stC.uiAnaCh));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpFeed (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpFeed : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
END_VAR
VAR
    (* FEED record accumulator *)
    stF : ST_SP_TrkCfg;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpFeed := TRUE;                (* FEED line built *)
    stF := g_astFeedCfg[i];
    s := CONCAT('FEED,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(stF.iDir))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.rWinStart, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.rWinLen, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.rPickAhead, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UdToStr(TIME_TO_UDINT(stF.tTimeout)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.rZBelt, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.stWorld.rDx, 4));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.stWorld.rDy, 4));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stF.stWorld.rRot, 6));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpCam (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpCam : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
END_VAR
VAR
    (* CAM record accumulator *)
    stV : ST_SP_VisionCfg;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpCam := TRUE;                 (* CAM line built *)
    stV := g_astCamCfg[i];
    s := CONCAT('CAM,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(stV.eDrv)));
    s := CONCAT(s, ',');  s := CONCAT(s, stV.sIp);
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stV.uiPort));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(stV.eTrig)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stV.astMap[1].rTrigDist, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stV.astMap[1].rRefSpeed, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stV.uiMaxItems));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(BOOL_TO_UINT(stV.bThInRad)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(REAL_TO_LREAL(stV.rMinScore), 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UdToStr(TIME_TO_UDINT(stV.tDelay)));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpCamMap (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpCamMap : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
    (* Sub-field parse index *)
    k : SINT;
END_VAR
VAR
    (* CAMMAP record accumulator *)
    stM : ST_SP_CamFeedMap;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpCamMap := TRUE;              (* CAMMAP line built *)
    stM := g_astCamCfg[i].astMap[k];
    s := CONCAT('CAMMAP,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(k))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(stM.iFeed))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stM.rYmin, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stM.rYmax, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stM.rTrigDist, 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stM.rRefSpeed, 2));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpPatt (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpPatt : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
END_VAR
VAR
    (* PATT record accumulator *)
    stP : ST_SP_PattDef;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpPatt := TRUE;                (* PATT line built *)
    stP := g_astPatt[i];
    s := CONCAT('PATT,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stP.uiRows));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stP.uiCols));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rDx, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rDy, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rRotStep, 6));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.pBase.rX, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.pBase.rY, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.pBase.rTh, 6));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stP.uiLayers));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rLayerH, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rZBase, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(stP.rTrigDist, 2));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpBatch / ExpBatchMix (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpBatch : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
END_VAR
VAR
    (* BATCH record accumulator *)
    stB : ST_SP_BatchDef;
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpBatch := TRUE;               (* BATCH line built *)
    stB := g_astBatchDef[i];
    s := CONCAT('BATCH,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(stB.iOutFeed))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(stB.uiPattId));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UdToStr(stB.udiQty));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(stB.eTrig)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(stB.iPriority))));
    out_sLine := s;
END_METHOD

METHOD ExpBatchMix : BOOL
VAR_INPUT
    (* Token/field parse index *)
    i : SINT;
    (* Sub-field parse index *)
    k : SINT;
END_VAR
VAR
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpBatchMix := TRUE;            (* BATCHMIX line built *)
    s := CONCAT('BATCHMIX,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(k))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(g_astBatchDef[i].aiMix[k]));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(g_astBatchDef[i].aiMixCnt[k]));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ExpShare / ExpShareR (parent SP_RecipeMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD ExpShare : BOOL
VAR_INPUT
    i : SINT;   (* feed *)
END_VAR
VAR
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpShare := TRUE;               (* SHARE line built *)
    s := CONCAT('SHARE,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(g_stShareCfg.aeStrat[i])));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(SINT_TO_UINT(g_stShareCfg.eMatch)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(BOOL_TO_UINT(g_stShareCfg.bStrictOrder)));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(g_stShareCfg.rPickBias, 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(g_stShareCfg.aiOutfeedMap[i]))));
    out_sLine := s;
END_METHOD

METHOD ExpShareR : BOOL
VAR_INPUT
    i : SINT;   (* feed *)
    k : SINT;   (* robot *)
END_VAR
VAR
    (* CSV line under construction *)
    s : STRING(200);
END_VAR
    ExpShareR := TRUE;              (* SHARER line built *)
    s := CONCAT('SHARER,', FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(i))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(DINT_TO_UINT(SINT_TO_DINT(k))));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(g_stShareCfg.arRatio[k], 3));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(g_stShareCfg.arRangeFrom[i][k], 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_LRealToStr(g_stShareCfg.arRangeTo[i][k], 2));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UdToStr(g_stShareCfg.audTypeMask[k]));
    s := CONCAT(s, ',');  s := CONCAT(s, FUN_SP_UiToStr(BOOL_TO_UINT(g_stShareCfg.aabManual[i][k])));
    out_sLine := s;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ImportLine (parent SP_RecipeMgr)
   Parse one recipe line and apply it to the configuration targets.
   Returns TRUE when the line was recognized (header or record applied).
   bErr flags rejected records (unknown index, malformed values).
   Production must be stopped during import (single-writer contract).
   ----------------------------------------------------------------------- *)
METHOD ImportLine : BOOL
VAR_INPUT
    (* Raw line from the recipe file *)
    sLine : STRING(200);
END_VAR
VAR
    (* Record keyword (first token of the line) *)
    sRec  : STRING(16);
    (* Token/field parse index *)
    i     : SINT;
    (* Sub-field parse index *)
    k     : SINT;
    (* Parsed floating-point value *)
    rL    : LREAL;
    (* Parsed integer value *)
    uiV   : UINT;
    (* CONV record accumulator *)
    stC   : ST_SP_ConvCfg;
    (* FEED record accumulator *)
    stF   : ST_SP_TrkCfg;
    (* CAM record accumulator *)
    stV   : ST_SP_VisionCfg;
    (* CAMMAP record accumulator *)
    stM   : ST_SP_CamFeedMap;
    (* PATT record accumulator *)
    stP   : ST_SP_PattDef;
    (* BATCH record accumulator *)
    stB   : ST_SP_BatchDef;
    (* Parsed camera IP address *)
    sIp   : STRING(16);
END_VAR
    ImportLine := FALSE;
    bErr := FALSE;
    sRec := FUN_SP_TokN(sLine, ',', 1);

    (* Comment / header: only the v2 format (angle tokens in DEGREES) is
       accepted; a v1 file would import radians as degrees and must be
       rejected loudly instead of silently mis-scaling rotations *)
    IF FIND(sRec, '#') = 1 THEN
        IF FIND(sLine, 'Recipe v2,') > 0 THEN
            sName := FUN_SP_TokN(sLine, ',', 2);
            ImportLine := TRUE;
        ELSE
            bErr := TRUE;       (* Legacy v1 (radians) or unknown version *)
        END_IF
        RETURN;
    END_IF
    IF LEN(sRec) = 0 THEN
        ImportLine := TRUE;     (* empty line: ignored *)
        RETURN;
    END_IF

    IF sRec = 'CONV' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_FEEDS);
        stC := g_astConvCfg[i];
        stC.bUsed := TRUE;
        stC.rEncScale := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 3), stC.rEncScale);
        uiV := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), 1);
        IF uiV = 0 THEN stC.iDir := -1; ELSE stC.iDir := 1; END_IF
        stC.rMaxSpeed := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 5), stC.rMaxSpeed);
        stC.rWinStart := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), stC.rWinStart);
        stC.rWinLen := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 7), stC.rWinLen);
        stC.rSlowAhead := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 8), stC.rSlowAhead);
        stC.rStopAhead := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 9), stC.rStopAhead);
        stC.rSlowFactor := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 10), stC.rSlowFactor);
        stC.eDrive := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 11), 0));
        stC.uiAnaCh := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 12), stC.uiAnaCh);
        g_astConvCfg[i] := stC;
        ImportLine := TRUE;

    ELSIF sRec = 'FEED' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_FEEDS);
        stF := g_astFeedCfg[i];
        stF.bUsed := TRUE;
        uiV := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 1);
        IF uiV = 0 THEN stF.iDir := -1; ELSE stF.iDir := 1; END_IF
        stF.rWinStart := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 4), stF.rWinStart);
        stF.rWinLen := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 5), stF.rWinLen);
        stF.rPickAhead := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), stF.rPickAhead);
        stF.tTimeout := UDINT_TO_TIME(FUN_SP_StrToUd(FUN_SP_TokN(sLine, ',', 7), TIME_TO_UDINT(stF.tTimeout)));
        stF.rZBelt := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 8), stF.rZBelt);
        stF.stWorld.rDx := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 9), stF.stWorld.rDx);
        stF.stWorld.rDy := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 10), stF.stWorld.rDy);
        stF.stWorld.rRot := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 11), stF.stWorld.rRot);
        stF.stWorld.rScale := 1.0;
        stF.stWorld.bValid := TRUE;
        g_astFeedCfg[i] := stF;
        ImportLine := TRUE;

    ELSIF sRec = 'CAM' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_CAMS);
        stV := g_astCamCfg[i];
        stV.bUsed := TRUE;
        stV.eDrv := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), SINT_TO_UINT(stV.eDrv)));
        sIp := FUN_SP_TokN(sLine, ',', 4);
        IF LEN(sIp) > 0 THEN stV.sIp := sIp; END_IF
        stV.uiPort := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 5), stV.uiPort);
        stV.eTrig := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 6), SINT_TO_UINT(stV.eTrig)));
        rL := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 7), -1.0);
        IF rL >= 0.0 THEN stV.astMap[1].rTrigDist := rL; END_IF
        rL := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 8), -1.0);
        IF rL >= 0.0 THEN stV.astMap[1].rRefSpeed := rL; END_IF
        uiV := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 9), 0);
        IF uiV > 0 THEN stV.uiMaxItems := uiV; END_IF
        stV.bThInRad := (FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 10), 0) > 0);
        rL := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 11), -1.0);
        IF rL >= 0.0 THEN stV.rMinScore := LREAL_TO_REAL(rL); END_IF
        stV.tDelay := UDINT_TO_TIME(FUN_SP_StrToUd(FUN_SP_TokN(sLine, ',', 12), TIME_TO_UDINT(stV.tDelay)));
        g_astCamCfg[i] := stV;
        ImportLine := TRUE;

    ELSIF sRec = 'CAMMAP' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_CAMS);
        k := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 0)), 1, GC_FEEDS);
        stM := g_astCamCfg[i].astMap[k];
        stM.iFeed := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), 0)), 0, GC_FEEDS);
        stM.rYmin := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 5), stM.rYmin);
        stM.rYmax := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), stM.rYmax);
        stM.rTrigDist := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 7), stM.rTrigDist);
        stM.rRefSpeed := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 8), stM.rRefSpeed);
        g_astCamCfg[i].astMap[k] := stM;
        ImportLine := TRUE;

    ELSIF sRec = 'PATT' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_PATT);
        stP := g_astPatt[i];
        stP.bUsed := TRUE;
        stP.uiRows := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), stP.uiRows);
        stP.uiCols := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), stP.uiCols);
        stP.rDx := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 5), stP.rDx);
        stP.rDy := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), stP.rDy);
        stP.rRotStep := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 7), stP.rRotStep);
        stP.pBase.rX := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 8), stP.pBase.rX);
        stP.pBase.rY := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 9), stP.pBase.rY);
        stP.pBase.rTh := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 10), stP.pBase.rTh);
        stP.uiLayers := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 11), stP.uiLayers);
        stP.rLayerH := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 12), stP.rLayerH);
        stP.rZBase := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 13), stP.rZBase);
        stP.rTrigDist := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 14), stP.rTrigDist);
        g_astPatt[i] := stP;
        ImportLine := TRUE;

    ELSIF sRec = 'BATCH' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_BATCHES);
        stB := g_astBatchDef[i];
        stB.bUsed := TRUE;
        stB.iOutFeed := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 0)), 1, GC_FEEDS);
        stB.uiPattId := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), stB.uiPattId);
        stB.udiQty := FUN_SP_StrToUd(FUN_SP_TokN(sLine, ',', 5), UDINT#0);
        stB.eTrig := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 6), 0));
        stB.iPriority := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 7), 0)), -100, 100);
        g_astBatchDef[i] := stB;
        ImportLine := TRUE;

    ELSIF sRec = 'BATCHMIX' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_BATCHES);
        k := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 0)), 1, GC_SEQ);
        g_astBatchDef[i].aiMix[k] := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), 0);
        g_astBatchDef[i].aiMixCnt[k] := FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 5), 0);
        ImportLine := TRUE;

    ELSIF sRec = 'SHARE' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_FEEDS);
        g_stShareCfg.aeStrat[i] := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 0));
        g_stShareCfg.eMatch := UINT_TO_SINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 4), 0));
        g_stShareCfg.bStrictOrder := (FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 5), 0) > 0);
        g_stShareCfg.rPickBias := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), g_stShareCfg.rPickBias);
        g_stShareCfg.aiOutfeedMap[i] := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 7), 0)), 0, GC_FEEDS);
        ImportLine := TRUE;

    ELSIF sRec = 'SHARER' THEN
        i := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 2), 0)), 1, GC_FEEDS);
        k := FUN_SP_ClampI(UINT_TO_DINT(FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 3), 0)), 1, GC_ROBOTS);
        g_stShareCfg.arRatio[k] := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 4), g_stShareCfg.arRatio[k]);
        g_stShareCfg.arRangeFrom[i][k] := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 5), g_stShareCfg.arRangeFrom[i][k]);
        g_stShareCfg.arRangeTo[i][k] := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, ',', 6), g_stShareCfg.arRangeTo[i][k]);
        g_stShareCfg.audTypeMask[k] := FUN_SP_StrToUd(FUN_SP_TokN(sLine, ',', 7), UDINT#0);
        g_stShareCfg.aabManual[i][k] := (FUN_SP_StrToUi(FUN_SP_TokN(sLine, ',', 8), 0) > 0);
        ImportLine := TRUE;

    ELSE
        bErr := TRUE;           (* Unknown record: rejected *)
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetError (parent SP_RecipeMgr)
   Read and clear the error flag (wiring-level diagnostics).
   ----------------------------------------------------------------------- *)
METHOD GetError : BOOL
    GetError := bErr;
    bErr := FALSE;
END_METHOD
