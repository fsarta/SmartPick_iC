(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 06_Pattern
   Worksheet : FB - SP_BatchMgr
   -----------------------------------------------------------------------------
   Purpose   : System batch manager: registry of batch definitions with
               per-outfeed activation, priority arbitration, progress
               tracking and completion events (user defined batches,
               multi-type targets, multi-layer placing - MotoPick 4 parity).

   Arbitration: when several batches target the same outfeed, the highest
   priority (iPriority, then lowest index) is started first.
   -----------------------------------------------------------------------------
   Methods:
     AddBatch      - register a definition (returns index, 0 = full)
     StartBatch    - activate by index
     StopBatch     - abort by index
     GetActive     - active batch index for an outfeed (0 = none)
     NotifyPlaced  - progress feedback from robots (via pattern gen stats)
     SyncProgress  - copy runtime progress from a pattern generator
   =============================================================================
*)

FUNCTION_BLOCK SP_BatchMgr
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    uiActive : UINT;            (* Number of running batches *)
    out_stDef  : ST_SP_BatchDef; (* Result buffer of GetDef *)
    out_stStat : ST_SP_BatchStat;(* Result buffer of GetStat *)
END_VAR
VAR
    (* Batch definitions (per outfeed, 1..GC_BATCHES) *)
    m_astDef  : ARRAY[1..8] OF ST_SP_BatchDef;
    (* Live batch progress (placed/remaining, 1..GC_BATCHES) *)
    m_astStat : ARRAY[1..8] OF ST_SP_BatchStat;
    m_udiIdGen: UDINT := 0;     (* Runtime batch id generator *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
THIS.CountActive();
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: CountActive (parent SP_BatchMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD CountActive : UINT
VAR
    (* Per-feed progress loop index *)
    i : SINT;
    (* Active batch counter *)
    uiC : UINT;
END_VAR
    uiC := 0;
    FOR i := 1 TO GC_BATCHES DO
        IF m_astStat[i].eState = ET_SP_BatchState#Running THEN
            uiC := uiC + 1;
        END_IF
    END_FOR
    uiActive := uiC;
    CountActive := uiC;             (* Active batch count *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddBatch (parent SP_BatchMgr)
   Register a batch definition. Returns the index (1..GC_BATCHES) or
   0 when the registry is full or the definition is invalid.
   ----------------------------------------------------------------------- *)
METHOD AddBatch : SINT
VAR_INPUT
    (* Batch definition to register *)
    stDef : ST_SP_BatchDef;
END_VAR
VAR
    (* Per-feed progress loop index *)
    i : SINT;
    (* Free registry slot (0 = none found) *)
    iFree : SINT;
END_VAR
    AddBatch := 0;
    IF (NOT stDef.bUsed) OR (stDef.iOutFeed < 1) OR (stDef.iOutFeed > GC_FEEDS) THEN
        RETURN;
    END_IF

    iFree := 0;
    FOR i := 1 TO GC_BATCHES DO
        IF NOT m_astDef[i].bUsed THEN
            iFree := i;
            EXIT;
        END_IF
    END_FOR
    IF iFree = 0 THEN
        RETURN;                     (* Registry full *)
    END_IF

    m_astDef[iFree] := stDef;
    m_astStat[iFree].eState := ET_SP_BatchState#Idle;
    m_astStat[iFree].udiDone := 0;
    m_astStat[iFree].udiGen  := 0;
    m_astStat[iFree].udiTrays:= 0;
    m_astStat[iFree].uiLayer := 0;
    AddBatch := iFree;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SetBatch (parent SP_BatchMgr)
   Store a batch definition at explicit slot iIdx (1..GC_BATCHES).
   ----------------------------------------------------------------------- *)
METHOD SetBatch : ET_SP_RetCode
VAR_INPUT
    iIdx  : SINT;
    stDef : ST_SP_BatchDef;
END_VAR
    SetBatch := ET_SP_RetCode#ErrParam;
    IF (iIdx < 1) OR (iIdx > GC_BATCHES) THEN
        RETURN;
    END_IF
    m_astDef[iIdx] := stDef;
    IF NOT stDef.bUsed THEN
        m_astStat[iIdx].eState := ET_SP_BatchState#Idle;
    ELSIF m_astStat[iIdx].eState <> ET_SP_BatchState#Running THEN
        m_astStat[iIdx].eState := ET_SP_BatchState#Idle;
        m_astStat[iIdx].udiDone := 0;
        m_astStat[iIdx].udiGen  := 0;
        m_astStat[iIdx].udiTrays:= 0;
        m_astStat[iIdx].uiLayer := 0;
    END_IF
    SetBatch := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StartBatch (parent SP_BatchMgr)
   Activate batch iIdx on its outfeed. Fails when another batch with
   higher-or-equal priority is already running on the same outfeed.
   ----------------------------------------------------------------------- *)
METHOD StartBatch : ET_SP_RetCode
VAR_INPUT
    (* Batch slot addressed by the call *)
    iIdx : SINT;
END_VAR
VAR
    (* Per-feed progress loop index *)
    i : SINT;
END_VAR
    StartBatch := ET_SP_RetCode#ErrParam;
    IF (iIdx < 1) OR (iIdx > GC_BATCHES) THEN
        RETURN;
    END_IF
    IF NOT m_astDef[iIdx].bUsed THEN
        RETURN;
    END_IF

    (* Priority arbitration on the target outfeed *)
    FOR i := 1 TO GC_BATCHES DO
        IF (i <> iIdx)
           AND (m_astStat[i].eState = ET_SP_BatchState#Running)
           AND (m_astDef[i].iOutFeed = m_astDef[iIdx].iOutFeed)
           AND (m_astDef[i].iPriority >= m_astDef[iIdx].iPriority) THEN
            StartBatch := ET_SP_RetCode#ErrBusy;
            RETURN;
        END_IF
    END_FOR

    m_udiIdGen := m_udiIdGen + 1;
    m_astStat[iIdx].eState   := ET_SP_BatchState#Running;
    m_astStat[iIdx].udiBatchId := m_udiIdGen;
    THIS.CountActive();
    StartBatch := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StopBatch (parent SP_BatchMgr)
   Abort a batch (operator stop / resiliency).
   ----------------------------------------------------------------------- *)
METHOD StopBatch : ET_SP_RetCode
VAR_INPUT
    (* Batch slot addressed by the call *)
    iIdx : SINT;
END_VAR
    StopBatch := ET_SP_RetCode#ErrParam;
    IF (iIdx < 1) OR (iIdx > GC_BATCHES) THEN
        RETURN;
    END_IF
    IF m_astStat[iIdx].eState = ET_SP_BatchState#Running THEN
        m_astStat[iIdx].eState := ET_SP_BatchState#Aborted;
        THIS.CountActive();
    END_IF
    StopBatch := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetActive (parent SP_BatchMgr)
   Highest-priority running batch index for outfeed iFeed (0 = none).
   ----------------------------------------------------------------------- *)
METHOD GetActive : SINT
VAR_INPUT
    (* Outfeed whose batch arbitration is requested *)
    iFeed : SINT;
END_VAR
VAR
    (* Per-feed progress loop index *)
    i : SINT;
    (* Highest-priority active batch slot for the outfeed *)
    iBest : SINT;
    (* Priority of the candidate being compared *)
    iPri  : SINT;
END_VAR
    iBest := 0;
    iPri  := -128;
    FOR i := 1 TO GC_BATCHES DO
        IF (m_astStat[i].eState = ET_SP_BatchState#Running)
           AND (m_astDef[i].iOutFeed = iFeed)
           AND (m_astDef[i].iPriority > iPri) THEN
            iPri  := m_astDef[i].iPriority;
            iBest := i;
        END_IF
    END_FOR
    GetActive := iBest;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetDef (parent SP_BatchMgr)
   Copy a definition into out_stDef. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD GetDef : BOOL
VAR_INPUT
    (* Batch slot addressed by the call *)
    iIdx : SINT;
END_VAR
    GetDef := FALSE;
    IF (iIdx >= 1) AND (iIdx <= GC_BATCHES) THEN
        IF m_astDef[iIdx].bUsed THEN
            out_stDef := m_astDef[iIdx];
            GetDef := TRUE;
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetStat (parent SP_BatchMgr)
   Copy runtime state into out_stStat. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD GetStat : BOOL
VAR_INPUT
    (* Batch slot addressed by the call *)
    iIdx : SINT;
END_VAR
    GetStat := FALSE;
    IF (iIdx >= 1) AND (iIdx <= GC_BATCHES) THEN
        out_stStat := m_astStat[iIdx];
        GetStat := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetId (parent SP_BatchMgr)
   Runtime batch id of definition iIdx (0 when unknown).
   ----------------------------------------------------------------------- *)
METHOD GetId : UDINT
VAR_INPUT
    (* Batch slot addressed by the call *)
    iIdx : SINT;
END_VAR
    GetId := UDINT#0;
    IF (iIdx >= 1) AND (iIdx <= GC_BATCHES) THEN
        GetId := m_astStat[iIdx].udiBatchId;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SyncProgress (parent SP_BatchMgr)
   Merge the runtime progress published by a pattern generator into the
   registry (called by SP_System per cycle per active outfeed).
   ----------------------------------------------------------------------- *)
METHOD SyncProgress : BOOL
VAR_INPUT
    iIdx    : SINT;             (* Batch index *)
    stStat  : ST_SP_BatchStat;  (* Pattern generator statistics *)
END_VAR
    SyncProgress := FALSE;
    IF (iIdx >= 1) AND (iIdx <= GC_BATCHES) THEN
        SyncProgress := TRUE;       (* Progress merged *)
        m_astStat[iIdx].udiDone := stStat.udiDone;
        m_astStat[iIdx].udiGen  := stStat.udiGen;
        m_astStat[iIdx].udiTrays:= stStat.udiTrays;
        m_astStat[iIdx].uiLayer := stStat.uiLayer;
        IF stStat.eState = ET_SP_BatchState#Done THEN
            m_astStat[iIdx].eState := ET_SP_BatchState#Done;
            THIS.CountActive();
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearAll (parent SP_BatchMgr)
   Reset the registry (recipe load).
   ----------------------------------------------------------------------- *)
METHOD ClearAll : UINT
VAR
    (* Per-feed progress loop index *)
    i : SINT;
END_VAR
    ClearAll := UINT#0;
    FOR i := 1 TO GC_BATCHES DO
        IF m_astStat[i].eState = ET_SP_BatchState#Running THEN
            ClearAll := ClearAll + UINT#1;   (* Cleared batch count *)
        END_IF
        m_astDef[i].bUsed := FALSE;
        m_astStat[i].eState := ET_SP_BatchState#Idle;
        m_astStat[i].udiDone := 0;
        m_astStat[i].udiGen  := 0;
        m_astStat[i].udiTrays:= 0;
    END_FOR
    THIS.CountActive();
END_METHOD
