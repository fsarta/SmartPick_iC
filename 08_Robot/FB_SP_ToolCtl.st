(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 08_Robot
   Worksheet : FB - SP_ToolCtl
   -----------------------------------------------------------------------------
   Purpose   : Tool signal sequencer for one robot (up to GC_TOOLS tools).

   Per tool signals (MotoPick 4 spec: PICK out, PLACE out, FEEDBACK in):
     - GripStart : PICK output ON, grip timer, feedback supervision
     - PlaceStart: PLACE output ON, release timer
     - bDone     : one-cycle pulse when the sequence finished
   Channels map to GVL_SP_Io arrays; explicit cfg channel overrides win
   over the automatic (robot-1)*GC_TOOLS + tool mapping.

   Trial run: bInhibit keeps outputs OFF while timing still runs and the
   feedback policy is bypassed (dry-run friendly).
   =============================================================================
*)

FUNCTION_BLOCK SP_ToolCtl
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bInhibit : BOOL;            (* TRUE = dry-run: outputs forced OFF *)
    uiDtMs   : UDINT;           (* Task period [ms] *)
END_VAR
VAR_OUTPUT
    (* Per-tool status published to HMI *)
    astStat  : ARRAY[1..GC_TOOLS] OF ST_SP_ToolStat;
    bAnyBusy : BOOL;            (* Any grip/release sequence running *)
    bDone    : BOOL;            (* One-cycle pulse: sequence finished *)
END_VAR
VAR
    m_iRob   : SINT := 1;       (* Owning robot id (channel mapping) *)
    m_astCfg : ARRAY[1..GC_TOOLS] OF ST_SP_ToolCfg;
    (* TRUE after a valid Configure() *)
    m_bCfgOk : BOOL;
    (* Dry-run inhibit: outputs frozen, sequences simulated *)
    m_bInhibit : BOOL;
    m_eOp    : SINT := 0;       (* 0=Idle 1=Grip 2=Release *)
    m_iTool  : SINT := 1;       (* Active tool *)
    m_uiT    : UDINT := 0;      (* Sequence timer [ms] *)
    m_uiDur  : UDINT := 0;      (* Sequence duration [ms] *)
    (* R-07 synchronized grip: TRUE while a GripSync sequence runs *)
    m_bSync  : BOOL;
    (* Cups covered by the running sync grip (1..GC_CUPS) *)
    m_uiSyncCups : UINT;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bDone := FALSE;
m_bInhibit := bInhibit;

IF m_eOp > 0 THEN
    m_uiT := m_uiT + uiDtMs;

    IF m_eOp = 1 THEN
        (* Grip: output stays ON; done when duration elapsed and the
           feedback policy is satisfied (inhibit bypasses feedback) *)
        astStat[m_iTool].bGripping := TRUE;
        IF m_uiT >= m_uiDur THEN
            IF bInhibit OR THIS.FbkOk(m_iTool) THEN
                m_eOp := 0;
                bDone := TRUE;
                astStat[m_iTool].bGripping := FALSE;
                astStat[m_iTool].bHolding := bInhibit OR THIS.FbkOk(m_iTool);
                astStat[m_iTool].udiPicks := astStat[m_iTool].udiPicks + 1;
                IF m_bSync THEN
                    (* R-07: capture the per-cup vacuum picture at grip end *)
                    THIS.CaptureCups();
                    m_bSync := FALSE;
                END_IF
            END_IF
            (* Feedback pending: keep waiting; timeout watchdog is robot FSM duty *)
        END_IF

    ELSIF m_eOp = 2 THEN
        (* Release: output ON until duration elapsed, then OFF *)
        IF m_uiT >= m_uiDur THEN
            THIS.WritePlace(m_iTool, FALSE);
            m_eOp := 0;
            bDone := TRUE;
            astStat[m_iTool].bHolding := FALSE;
            astStat[m_iTool].udiPlaces := astStat[m_iTool].udiPlaces + 1;
        END_IF
    END_IF
END_IF

THIS.RefreshFbk();
bAnyBusy := (m_eOp > 0);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_ToolCtl)
   Bind tools and owner robot for the automatic channel mapping.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Tool configurations (cup offsets, timings) *)
    astTools : ARRAY[1..GC_TOOLS] OF ST_SP_ToolCfg;
    (* Owner robot id (1..GC_ROBOTS) *)
    iRobot   : SINT;
END_VAR
    Configure := ET_SP_RetCode#Done;
    IF (iRobot < 1) OR (iRobot > GC_ROBOTS) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    m_iRob   := iRobot;
    m_astCfg := astTools;
    m_bCfgOk := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AutoCh (parent SP_ToolCtl) - internal
   Automatic I/O channel for (robot, tool): (robot-1)*GC_TOOLS + tool.
   ----------------------------------------------------------------------- *)
METHOD AutoCh : UINT
VAR_INPUT
    (* Tool selector (1-based, 0 = any) *)
    iTool : SINT;
END_VAR
    AutoCh := DINT_TO_UINT(SINT_TO_DINT(m_iRob - 1) * SINT_TO_DINT(GC_TOOLS)
                           + SINT_TO_DINT(iTool));
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ChPick / ChPlace / ChFbk (parent SP_ToolCtl) - internal
   Effective channels: cfg override when > 0, automatic otherwise.
   ----------------------------------------------------------------------- *)
METHOD ChPick : UINT
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    IF m_astCfg[iTool].uiPickOutCh > UINT#0 THEN
        ChPick := m_astCfg[iTool].uiPickOutCh;
    ELSE
        ChPick := THIS.AutoCh(iTool);
    END_IF
END_METHOD

METHOD ChPlace : UINT
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    IF m_astCfg[iTool].uiPlaceOutCh > UINT#0 THEN
        ChPlace := m_astCfg[iTool].uiPlaceOutCh;
    ELSE
        ChPlace := THIS.AutoCh(iTool);
    END_IF
END_METHOD

METHOD ChFbk : UINT
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    IF m_astCfg[iTool].uiFbkInCh > UINT#0 THEN
        ChFbk := m_astCfg[iTool].uiFbkInCh;
    ELSE
        ChFbk := THIS.AutoCh(iTool);
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: WritePick / WritePlace (parent SP_ToolCtl) - internal
   Physical output write with dry-run inhibition.
   ----------------------------------------------------------------------- *)
METHOD WritePick : BOOL
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
    (* TRUE = channel ON, FALSE = OFF *)
    bOn   : BOOL;
END_VAR
    WritePick := FALSE;
    IF m_bInhibit THEN
        RETURN;                     (* Trial run: outputs stay OFF *)
    END_IF
    GVL_SP_Io.abPickOut[THIS.ChPick(iTool)] := bOn;
    WritePick := TRUE;              (* Output written *)
END_METHOD

METHOD WritePlace : BOOL
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
    (* TRUE = channel ON, FALSE = OFF *)
    bOn   : BOOL;
END_VAR
    WritePlace := FALSE;
    IF m_bInhibit THEN
        RETURN;                     (* Trial run: outputs stay OFF *)
    END_IF
    GVL_SP_Io.abPlaceOut[THIS.ChPlace(iTool)] := bOn;
    WritePlace := TRUE;             (* Output written *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FbkOk (parent SP_ToolCtl) - internal
   TRUE when the tool feedback input confirms the part (or the tool has
   no feedback wired: channel above the array size reads FALSE, handled
   by the robot grip watchdog).
   ----------------------------------------------------------------------- *)
METHOD FbkOk : BOOL
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    FbkOk := GVL_SP_Io.abToolFbkIn[THIS.ChFbk(iTool)];
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GripStart (parent SP_ToolCtl)
   Start a grip sequence on tool iTool (single cup or whole head, the
   output channel is common). Clears the synchronized flag.
   ----------------------------------------------------------------------- *)
METHOD GripStart : ET_SP_RetCode
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    GripStart := ET_SP_RetCode#Done;
    IF NOT m_bCfgOk THEN
        GripStart := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF
    IF (iTool < 1) OR (iTool > GC_TOOLS) OR (NOT m_astCfg[iTool].bUsed) THEN
        GripStart := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF m_eOp <> 0 THEN
        GripStart := ET_SP_RetCode#ErrBusy;
        RETURN;
    END_IF

    m_iTool := iTool;
    m_eOp   := 1;
    m_bSync := FALSE;           (* Plain single sequence *)
    m_uiT   := UDINT#0;
    m_uiDur := TIME_TO_UDINT(m_astCfg[iTool].tGrip);
    THIS.WritePick(iTool, TRUE);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GripSync (parent SP_ToolCtl) - R-07 synchronized multi-grip
   Grip the whole head in ONE sequence and capture the per-cup vacuum
   feedback picture at completion (astStat[..].abCupFbk / uiCupOk).
   Physically identical to GripStart (one common valve); the difference
   is the per-cup diagnostic capture consumed by the robot GripEval state.
   ----------------------------------------------------------------------- *)
METHOD GripSync : ET_SP_RetCode
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
    (* Cups covered by this grip 1..GC_CUPS *)
    uiCups : UINT;
END_VAR
VAR
    (* Clamped cup count (defensive) *)
    uiN : UINT;
END_VAR
    GripSync := ET_SP_RetCode#Done;
    IF NOT m_bCfgOk THEN
        GripSync := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF
    IF (iTool < 1) OR (iTool > GC_TOOLS) OR (NOT m_astCfg[iTool].bUsed) THEN
        GripSync := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF m_eOp <> 0 THEN
        GripSync := ET_SP_RetCode#ErrBusy;
        RETURN;
    END_IF

    uiN := uiCups;
    IF uiN < UINT#1 THEN
        uiN := UINT#1;
    END_IF
    IF uiN > UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS)) THEN
        uiN := UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS));
    END_IF

    m_iTool := iTool;
    m_eOp   := 1;
    m_bSync := TRUE;
    m_uiSyncCups := uiN;
    m_uiT   := UDINT#0;
    m_uiDur := TIME_TO_UDINT(m_astCfg[iTool].tGrip);
    THIS.WritePick(iTool, TRUE);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: PlaceStart (parent SP_ToolCtl)
   Start a release sequence on tool iTool.
   ----------------------------------------------------------------------- *)
METHOD PlaceStart : ET_SP_RetCode
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    PlaceStart := ET_SP_RetCode#Done;
    IF NOT m_bCfgOk THEN
        PlaceStart := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF
    IF (iTool < 1) OR (iTool > GC_TOOLS) OR (NOT m_astCfg[iTool].bUsed) THEN
        PlaceStart := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF m_eOp <> 0 THEN
        PlaceStart := ET_SP_RetCode#ErrBusy;
        RETURN;
    END_IF

    m_iTool := iTool;
    m_eOp   := 2;
    m_uiT   := UDINT#0;
    m_uiDur := TIME_TO_UDINT(m_astCfg[iTool].tRelease);
    THIS.WritePlace(iTool, TRUE);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AbortAll (parent SP_ToolCtl)
   Immediate outputs OFF (fault path / estop chain).
   ----------------------------------------------------------------------- *)
METHOD AbortAll : BOOL
VAR
    (* Tool loop index (abort scan) *)
    i : SINT;
END_VAR
    AbortAll := TRUE;               (* Outputs forced OFF *)
    m_eOp := 0;
    FOR i := 1 TO GC_TOOLS DO
        IF m_astCfg[i].bUsed THEN
            THIS.WritePick(i, FALSE);
            THIS.WritePlace(i, FALSE);
            astStat[i].bGripping := FALSE;
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: RefreshFbk (parent SP_ToolCtl) - internal
   Publish raw feedback levels per tool.
   ----------------------------------------------------------------------- *)
METHOD RefreshFbk : BOOL
VAR
    (* Tool loop index (publish) *)
    i : SINT;
END_VAR
    RefreshFbk := TRUE;             (* Feedback levels published *)
    FOR i := 1 TO GC_TOOLS DO
        IF m_astCfg[i].bUsed THEN
            astStat[i].bFbk := GVL_SP_Io.abToolFbkIn[THIS.ChFbk(i)];
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FbkCup (parent SP_ToolCtl) - R-07 per-cup vacuum feedback
   TRUE when cup iCup of tool iTool confirms the part. Per-cup channels
   are used when configured (auiCupFbkCh[iCup] > 0); otherwise the tool
   level feedback channel is the only information available and it is
   returned for every cup (single-point verification semantics).
   ----------------------------------------------------------------------- *)
METHOD FbkCup : BOOL
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
    (* Cup index inside the tool (1-based) *)
    iCup  : SINT;
END_VAR
VAR
    (* Resolved feedback channel for the cup *)
    uiCh : UINT;
END_VAR
    uiCh := UINT#0;
    IF (iTool >= 1) AND (iTool <= GC_TOOLS) THEN
        IF (iCup >= 1) AND (iCup <= GC_CUPS) THEN
            uiCh := m_astCfg[iTool].auiCupFbkCh[iCup];
        END_IF
    END_IF
    IF uiCh > UINT#0 THEN
        FbkCup := GVL_SP_Io.abToolFbkIn[uiCh];
    ELSE
        FbkCup := GVL_SP_Io.abToolFbkIn[THIS.ChFbk(iTool)];
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CaptureCups (parent SP_ToolCtl) - internal (R-07)
   Snapshot the per-cup vacuum feedback into the tool status after a
   synchronized grip (called by the body on GripSync completion).
   ----------------------------------------------------------------------- *)
METHOD CaptureCups : BOOL
VAR
    (* Cup loop index (snapshot scan) *)
    i : SINT;
    (* Confirmed-cup counter *)
    uiOk : UINT;
END_VAR
    CaptureCups := TRUE;            (* Per-cup snapshot taken *)
    uiOk := UINT#0;
    FOR i := 1 TO GC_CUPS DO
        IF i <= UINT_TO_DINT(m_uiSyncCups) THEN
            astStat[m_iTool].abCupFbk[i] := bInhibit OR THIS.FbkCup(m_iTool, i);
        ELSE
            astStat[m_iTool].abCupFbk[i] := FALSE;
        END_IF
        IF astStat[m_iTool].abCupFbk[i] THEN
            uiOk := uiOk + UINT#1;
        END_IF
    END_FOR
    astStat[m_iTool].uiCupOk := uiOk;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: HoldingOf (parent SP_ToolCtl)
   TRUE when the tool currently holds a part (verification helper).
   ----------------------------------------------------------------------- *)
METHOD HoldingOf : BOOL
VAR_INPUT
    (* Tool selector *)
    iTool : SINT;
END_VAR
    HoldingOf := astStat[iTool].bHolding;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ResetCounters (parent SP_ToolCtl)
   Clear pick/place counters (production reset).
   ----------------------------------------------------------------------- *)
METHOD ResetCounters : BOOL
VAR
    (* Tool loop index (publish) *)
    i : SINT;
END_VAR
    ResetCounters := TRUE;          (* Tool counters cleared *)
    FOR i := 1 TO GC_TOOLS DO
        astStat[i].udiPicks := UDINT#0;
        astStat[i].udiPlaces := UDINT#0;
    END_FOR
END_METHOD
