(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 06_Pattern
   Worksheet : FB - SP_PatternGen
   -----------------------------------------------------------------------------
   Purpose   : Per-outfeed placement pattern generator (MotoPick 4 parity):

     - Periodically generated pattern: a new pattern instance is issued
       once the outfeed conveyor has traveled the configured distance.
     - Tray detection via external sensor: a light barrier edge starts a
       new tray instance; slot information comes from the pattern.
     - Multi-layer placing: the next layer is generated only when the
       current layer is fully placed (NotifyPlaced), giving the stacked
       Z progression (rZBase + layer * rLayerH).
     - Type mix: slots get their target type from the batch mix sequence.

   Generated targets are drained by SP_System (GetNextTarget) and inserted
   into the outfeed SP_TrkFeed queue as bTarget records.
   =============================================================================
*)

FUNCTION_BLOCK SP_PatternGen
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    bActive   : BOOL;             (* Generating (batch running) *)
    out_stTarget : ST_SP_TrkItem; (* Drained target (GetNextTarget) *)
    uiGenPending : UINT;          (* Targets waiting for drain *)
    stStat    : ST_SP_BatchStat;  (* Runtime batch state *)
END_VAR
VAR
    m_stDef   : ST_SP_PattDef;    (* Active pattern *)
    m_stBatch : ST_SP_BatchDef;   (* Active batch *)
    m_bRun    : BOOL;             (* Batch active *)
    m_bPatOk  : BOOL;             (* Pattern loaded *)
    (* Frame binding (from outfeed config) *)
    m_stWorld : ST_SP_Transf2D;   (* Feed -> world *)
    m_rZBelt  : LREAL;            (* Belt surface Z *)
    m_iDir    : SINT;             (* Belt direction sign *)
    m_bCfgOk  : BOOL;
    (* Trigger engine *)
    m_rLastGen: LREAL;            (* Encoder at last pattern instance *)
    m_bInit   : BOOL;
    m_iSlot   : UINT;             (* Next slot to generate (1-based) *)
    m_iMix    : UINT;             (* Current mix entry *)
    m_iMixCnt : UINT;             (* Slots consumed of current mix entry *)
    m_uiLayer : UINT;             (* Current layer (0-based) *)
    m_uiPlacedInLayer : UINT;     (* Placed slots of current layer *)
    m_bLayerOpen : BOOL;          (* TRUE while current layer not exhausted *)
    (* Out-queue 1..GC_VIS_MAX2 *)
    m_astT    : ARRAY[1..32] OF ST_SP_TrkItem;
    (* Targets waiting in the out-queue *)
    m_iTCnt   : SINT := 0;
    (* Drain index for GetTarget *)
    m_iTRd    : SINT := 0;
    (* Id of the running batch (0 = idle) *)
    m_udiBatchId : UDINT := 0;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bActive := m_bRun;
uiGenPending := SINT_TO_UINT(m_iTCnt - m_iTRd);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_PatternGen)
   Bind the outfeed frame (world transform, belt height, direction).
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    stWorld : ST_SP_Transf2D;   (* Feed -> world transform *)
    rZBelt  : LREAL;            (* Belt surface Z [mm] *)
    iDir    : SINT;             (* Belt direction sign *)
END_VAR
    Configure := ET_SP_RetCode#Done;
    IF (iDir <> 1) AND (iDir <> -1) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    m_stWorld := stWorld;
    m_rZBelt  := rZBelt;
    m_iDir    := iDir;
    m_bCfgOk  := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StartBatch (parent SP_PatternGen)
   Start a batch: bind pattern + batch definition, reset layer state.
   ----------------------------------------------------------------------- *)
METHOD StartBatch : ET_SP_RetCode
VAR_INPUT
    (* Batch definition (quantities, mix, layer Z) *)
    stDef    : ST_SP_BatchDef;
    (* Pattern definition (rows, cols, pitch, offsets) *)
    stPatt   : ST_SP_PattDef;
    (* Caller-assigned batch id *)
    udiBatchId : UDINT;
END_VAR
    StartBatch := ET_SP_RetCode#Done;

    IF NOT m_bCfgOk THEN
        StartBatch := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF
    IF (NOT stPatt.bUsed) OR (NOT stDef.bUsed) THEN
        StartBatch := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF (stPatt.uiRows * stPatt.uiCols) > UDINT_TO_UINT(SINT_TO_UDINT(GC_PATT_SLOTS)) THEN
        StartBatch := ET_SP_RetCode#ErrRange;
        RETURN;
    END_IF

    m_stDef   := stPatt;
    m_stBatch := stDef;
    m_udiBatchId := udiBatchId;
    m_bPatOk  := TRUE;
    m_bRun    := TRUE;

    (* Layer 0 generation is immediate for Distance/BatchStart triggers,
       sensor mode waits for the tray edge (OnSensor). *)
    m_uiLayer := 0;
    m_uiPlacedInLayer := 0;
    m_bLayerOpen := FALSE;
    m_bInit  := FALSE;
    m_iSlot  := 0;
    m_iMix   := 1;
    m_iMixCnt := 0;
    m_iTCnt  := 0;
    m_iTRd   := 0;

    stStat.eState := ET_SP_BatchState#Running;
    stStat.udiBatchId := udiBatchId;
    stStat.udiDone := 0;
    stStat.udiGen  := 0;
    stStat.udiTrays:= 0;
    stStat.uiLayer := 0;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AbortBatch (parent SP_PatternGen)
   Stop generation and drop pending targets.
   ----------------------------------------------------------------------- *)
METHOD AbortBatch : BOOL
VAR
    (* Mix entry loop index *)
    i : SINT;
END_VAR
    AbortBatch := TRUE;             (* Generation stopped *)
    m_bRun := FALSE;
    FOR i := 1 TO GC_VIS_MAX2 DO
        m_astT[i].bValid := FALSE;
    END_FOR
    m_iTCnt := 0;
    m_iTRd  := 0;
    stStat.eState := ET_SP_BatchState#Aborted;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OnSensor (parent SP_PatternGen)
   Light barrier edge from the tray sensor (call on rising edge with the
   current outfeed encoder value).
   ----------------------------------------------------------------------- *)
METHOD OnSensor : BOOL
VAR_INPUT
    rEncNow : LREAL;    (* Current outfeed belt encoder [mm] *)
END_VAR
    OnSensor := FALSE;
    IF m_bRun AND m_bPatOk THEN
        m_rLastGen := rEncNow;      (* Stamp encoder for the new slots *)
        THIS.NewTray();
        OnSensor := TRUE;           (* New tray generated *)
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Engine (parent SP_PatternGen)
   Trigger evaluation for Distance mode; called cyclically by SP_System.
   ----------------------------------------------------------------------- *)
METHOD Engine : BOOL
VAR_INPUT
    rEncNow : LREAL;    (* Outfeed belt encoder [mm] *)
END_VAR
VAR
    (* Belt travel since the last generated slot [mm] *)
    rTrav : LREAL;
END_VAR
    Engine := TRUE;                 (* Trigger evaluation executed *)
    IF NOT (m_bRun AND m_bPatOk) THEN
        RETURN;
    END_IF

    IF NOT m_bInit THEN
        m_rLastGen := rEncNow;
        m_bInit := TRUE;
        (* First instance for non-sensor modes *)
        IF m_stBatch.eTrig <> ET_SP_PattTrig#Sensor THEN
            THIS.NewTray();
        END_IF
        RETURN;
    END_IF

    IF m_stBatch.eTrig = ET_SP_PattTrig#Distance THEN
        rTrav := ABS(rEncNow - m_rLastGen);
        IF rTrav >= m_stDef.rTrigDist THEN
            m_rLastGen := rEncNow;      (* Stamp encoder for the new slots *)
            THIS.NewTray();
        END_IF
    END_IF
    (* BatchStart: single instance (already generated at init) *)
    (* Sensor: instances driven by OnSensor edges; stamp before NewTray *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: NewTray (parent SP_PatternGen) - internal
   Generate layer m_uiLayer of a new tray instance.
   ----------------------------------------------------------------------- *)
METHOD NewTray : BOOL
VAR
    (* Sequential slot number inside the layer *)
    uiSlotNo : UINT;
    (* Slot placement pose in the tray frame (X/Y/Z) *)
    rU, rV, rZ : LREAL;
    (* Slot placement orientation [deg] *)
    rTh : LREAL;
    (* Target record built for the queue *)
    stT : ST_SP_TrkItem;
    (* Row/column indices of the slot in the grid *)
    uiRow, uiCol : UINT;
END_VAR
    NewTray := FALSE;
    IF NOT (m_bRun AND m_bPatOk) THEN
        RETURN;
    END_IF
    NewTray := TRUE;                (* Tray generation started *)

    (* Absolute world Z of the current layer *)
    rZ := m_stDef.rZBase + UDINT_TO_LREAL(UINT_TO_UDINT(m_uiLayer)) * m_stDef.rLayerH;

    uiSlotNo := 0;
    FOR uiRow := 1 TO m_stDef.uiRows DO
        FOR uiCol := 1 TO m_stDef.uiCols DO
            uiSlotNo := uiSlotNo + 1;

            (* Slot position in feed frame *)
            rU := m_stDef.pBase.rX + UDINT_TO_LREAL(UINT_TO_UDINT(uiCol - 1)) * m_stDef.rDx;
            rV := m_stDef.pBase.rY + UDINT_TO_LREAL(UINT_TO_UDINT(uiRow - 1)) * m_stDef.rDy;

            IF m_stDef.rRotStep <> 0.0 THEN
                rTh := FUN_SP_NormAng(m_stDef.pBase.rTh
                       + UDINT_TO_LREAL(UINT_TO_UDINT(uiSlotNo - 1)) * m_stDef.rRotStep);
            ELSE
                rTh := m_stDef.pBase.rTh;
            END_IF

            stT.udiId    := UDINT#0;          (* Assigned by the camera path *)
            stT.uiTypeId := THIS.MixType();
            stT.rBeltCap := rV;               (* Feed frame: upstream offset *)
            stT.rEncCap  := m_rLastGen;       (* Stamped by the caller *)
            stT.p2World.rX  := FUN_SP_TrfX(m_stWorld, rU, rV);
            stT.p2World.rY  := FUN_SP_TrfY(m_stWorld, rU, rV);
            stT.p2World.rTh := FUN_SP_NormAng(m_stWorld.rRot + rTh);
            stT.rWeight := 0.0;
            stT.rScore  := 1.0;
            stT.eState  := ET_SP_ItemState#Tracked;
            stT.iReservedBy := GC_ID_NONE;
            stT.uiAttempts  := 0;
            stT.bTarget  := TRUE;
            stT.udiBatchId := m_udiBatchId;
            stT.uiSlot := uiSlotNo;
            stT.rZWorld := rZ;                (* Layer Z for the place move *)
            stT.tAgeMs := UDINT#0;
            stT.bValid := TRUE;

            THIS.PushTarget(stT);
        END_FOR
    END_FOR

    stStat.udiTrays := stStat.udiTrays + 1;
    stStat.uiLayer  := m_uiLayer;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: MixType (parent SP_PatternGen) - internal
   Type of the next slot from the batch mix sequence: round robin over the
   mix entries, each producing aiMixCnt slots per layer.
   ----------------------------------------------------------------------- *)
METHOD MixType : UINT
VAR
    (* Mix entry loop index *)
    i      : SINT;
    (* Type id candidate from the mix table *)
    uiT    : UINT;
    (* Length of the mix sequence table *)
    uiSeqMax : UINT;
END_VAR
    uiSeqMax := SINT_TO_UINT(GC_SEQ);

    (* Skip empty entries: advance until a usable one is found *)
    IF (m_stBatch.aiMix[m_iMix] = 0) OR (m_stBatch.aiMixCnt[m_iMix] = 0) THEN
        FOR i := 1 TO GC_SEQ DO
            m_iMix := m_iMix + 1;
            IF m_iMix > uiSeqMax THEN
                m_iMix := 1;
            END_IF
            IF (m_stBatch.aiMix[m_iMix] > 0) AND (m_stBatch.aiMixCnt[m_iMix] > 0) THEN
                EXIT;
            END_IF
        END_FOR
        m_iMixCnt := 0;
    END_IF

    uiT := m_stBatch.aiMix[m_iMix];
    IF uiT = 0 THEN
        uiT := 1;                   (* Degenerate mix: default type 1 *)
    END_IF

    (* Consume one slot of the current entry; advance on exhaustion *)
    m_iMixCnt := m_iMixCnt + 1;
    IF m_iMixCnt >= m_stBatch.aiMixCnt[m_iMix] THEN
        m_iMixCnt := 0;
        m_iMix := m_iMix + 1;
        IF m_iMix > uiSeqMax THEN
            m_iMix := 1;
        END_IF
    END_IF

    MixType := uiT;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: PushTarget (parent SP_PatternGen) - internal
   Append a generated target to the out-queue.
   ----------------------------------------------------------------------- *)
METHOD PushTarget : ET_SP_RetCode
VAR_INPUT
    stT : ST_SP_TrkItem;    (* Target record to enqueue *)
END_VAR
    PushTarget := ET_SP_RetCode#ErrFull;
    IF m_iTCnt < GC_VIS_MAX2 THEN
        m_iTCnt := m_iTCnt + 1;
        m_astT[m_iTCnt] := stT;
        stStat.udiGen := stStat.udiGen + 1;
        PushTarget := ET_SP_RetCode#Done;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetNextTarget (parent SP_PatternGen)
   Drain one generated target into out_stTarget. TRUE while available.
   ----------------------------------------------------------------------- *)
METHOD GetNextTarget : BOOL
    GetNextTarget := FALSE;
    IF m_iTRd < m_iTCnt THEN
        m_iTRd := m_iTRd + 1;
        out_stTarget := m_astT[m_iTRd];
        GetNextTarget := TRUE;
    ELSE
        m_iTCnt := 0;
        m_iTRd  := 0;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: NotifyPlaced (parent SP_PatternGen)
   Robot confirms one placed target of the current layer. When the layer
   is complete: advance layer or close the batch (quantity reached).
   ----------------------------------------------------------------------- *)
METHOD NotifyPlaced : ET_SP_RetCode
VAR_INPUT
    uiSlot : UINT;      (* Placed slot number (informational) *)
END_VAR
VAR
    (* Slots of one layer (rows x cols) *)
    uiLayerSlots : UINT;
END_VAR
    NotifyPlaced := ET_SP_RetCode#ErrState;
    IF NOT m_bRun THEN
        RETURN;
    END_IF

    m_uiPlacedInLayer := m_uiPlacedInLayer + 1;
    stStat.udiDone := stStat.udiDone + 1;
    uiLayerSlots := m_stDef.uiRows * m_stDef.uiCols;

    IF stStat.udiDone >= m_stBatch.udiQty THEN
        m_bRun := FALSE;
        stStat.eState := ET_SP_BatchState#Done;
        NotifyPlaced := ET_SP_RetCode#Done;
        RETURN;
    END_IF

    IF m_uiPlacedInLayer >= uiLayerSlots THEN
        (* Layer complete: next tray instance will use the next layer
           until uiLayers exhausted, then restart at layer 0 (new stack) *)
        m_uiPlacedInLayer := 0;
        m_uiLayer := m_uiLayer + 1;
        IF m_uiLayer >= m_stDef.uiLayers THEN
            m_uiLayer := 0;
        END_IF
        stStat.uiLayer := m_uiLayer;
        IF m_stBatch.eTrig = ET_SP_PattTrig#BatchStart THEN
            THIS.NewTray();
        END_IF
    END_IF
    NotifyPlaced := ET_SP_RetCode#Done;
END_METHOD
