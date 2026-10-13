(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 13_MultiGrip
   Worksheet : FB - SP_GripPlanner
   -----------------------------------------------------------------------------
   Purpose   : Advanced multi-grip cluster planner (roadmap R-07).
               Pure decision logic, no storage access: the item queue
               (SP_ItemQueue.ReserveCluster) drives it with a pull API:

     Begin(stReq, p2Anchor, uiTypeA)   open a planning session; the anchor
                                       (front item) becomes member 1 / cup 1.
     OfferCand(iIdx, stIt) : BOOL      queue offers one candidate (capture
                                       world pose). TRUE = add to cluster.
     Finish                            compute the synchronized TCP pose,
                                       prune members that violate the match
                                       tolerance, run the CoG audit and
                                       publish the plan (out_* variables).

   Matching rule (per candidate):
     Required world position of cup c (c = 2..uiCups, unassigned):
         req_c = anchor_xy + Rot(anchor_yaw) * (cup_c - cup_1)
     The candidate is taken by the cup with the smallest distance to its
     required position, provided that:
       - distance <= rMatchTol
       - type rule respected (bSingleType)
       - payload rule respected (running weight sum <= rMaxWeight)
       - gap rule respected (>= rMinGap to every accepted member)
   Candidates behind other accepted items are implicitly covered by the
   gap rule; the front-to-rear offering order of the queue keeps the
   assignment deterministic.

   TCP computation (Finish):
     yaw  = circular mean of member yaws            (FUN_SP_FitYaw)
     xy   = mean of (item_k - Rot(yaw) * cup_k)     (least squares)
     res  = worst per-cup residual                  (FUN_SP_ClusterResidual)
     Members with residual > rMatchTol are dropped (worst first, anchor
     last); the plan degrades to a plain single pick when < 2 remain or
     when the CoG audit fails.

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_GripPlanner
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    out_bOk   : BOOL;           (* Plan valid (Finish called) *)
    out_bSync : BOOL;           (* TRUE = synchronized multi-pick approved *)
    out_uiN   : UINT;           (* Final members 1..GC_CUPS *)
    (* Queue slot per member (1 = anchor) *)
    out_aiIdx : ARRAY[1..GC_CUPS] OF SINT;
    (* Cup id per member (1 = anchor cup) *)
    out_aCup  : ARRAY[1..GC_CUPS] OF SINT;
    (* Member item poses (capture frame, world) *)
    out_astP  : ARRAY[1..GC_CUPS] OF ST_SP_Pose3D;
    (* Synchronized TCP pose at the pick event (capture frame) *)
    out_stTcp : ST_SP_Pose3D;
    out_rW    : REAL;           (* Total accepted weight [g] *)
    out_rCog  : LREAL;          (* CoG offset from TCP [mm], 0 = unknown *)
END_VAR
VAR
    (* TRUE between Begin and Finish *)
    m_bRun    : BOOL;
    (* Working copy of the cluster request (rules + cup layout) *)
    m_stReq   : ST_SP_ClReq;
    (* Anchor world pose (XY + yaw = matching reference frame) *)
    m_p2A     : ST_SP_Pose2D;
    (* Anchor product type (single-type rule) *)
    m_uiTypeA : UINT;
    (* Accepted member count *)
    m_uiN     : UINT;
    (* Queue slot per accepted member *)
    m_aiIdx   : ARRAY[1..GC_CUPS] OF SINT;
    (* Cup id per accepted member *)
    m_aCup    : ARRAY[1..GC_CUPS] OF SINT;
    (* Accepted member poses (world, capture frame) *)
    m_astP    : ARRAY[1..GC_CUPS] OF ST_SP_Pose3D;
    (* Accepted member weights [g] (CoG audit) *)
    m_arW     : ARRAY[1..GC_CUPS] OF REAL;
    (* Cup occupancy flags (cup 1 = anchor, always used) *)
    m_abCupUsed : ARRAY[1..GC_CUPS] OF BOOL;
    (* Running weight sum [g] *)
    m_rW      : REAL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Stateless body: all work happens in the pull methods; the outputs keep
   the last published plan until the next Finish. *)
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Begin (parent SP_GripPlanner)
   Open a planning session. The anchor becomes member 1 on cup 1.
   ----------------------------------------------------------------------- *)
METHOD Begin : ET_SP_RetCode
VAR_INPUT
    (* Cluster request (rules + cup layout, copied) *)
    stReq    : ST_SP_ClReq;
    (* Anchor world pose (capture frame) *)
    p2Anchor : ST_SP_Pose2D;
    (* Anchor product type *)
    uiTypeA  : UINT;
END_VAR
VAR
    (* Cup loop index (state reset) *)
    i : SINT;
END_VAR
    Begin := ET_SP_RetCode#ErrParam;
    IF (stReq.uiCups < UINT#1)
       OR (stReq.uiCups > UDINT_TO_UINT(SINT_TO_UDINT(GC_CUPS))) THEN
        RETURN;                 (* Invalid head size *)
    END_IF
    IF stReq.rMatchTol <= 0.0 THEN
        RETURN;                 (* A tolerance is mandatory *)
    END_IF

    m_stReq := stReq;
    m_p2A := p2Anchor;
    m_uiTypeA := uiTypeA;
    m_uiN := UINT#1;            (* Anchor pre-accepted *)
    m_rW := 0.0;
    FOR i := 1 TO GC_CUPS DO
        m_aiIdx[i] := 0;
        m_aCup[i]  := 0;
        m_abCupUsed[i] := FALSE;
        m_astP[i].rX := 0.0;  m_astP[i].rY := 0.0;
        m_astP[i].rZ := 0.0;  m_astP[i].rTh := 0.0;
        m_arW[i] := 0.0;
    END_FOR
    m_aiIdx[1] := 0;            (* Slot id filled by the queue at commit *)
    m_aCup[1]  := 1;
    m_abCupUsed[1] := TRUE;
    m_bRun := TRUE;
    Begin := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OfferCand (parent SP_GripPlanner)
   Offer one candidate item to the open session. TRUE = accepted on a
   cup (queue MUST commit it when Finish reports it in the final plan).
   ----------------------------------------------------------------------- *)
METHOD OfferCand : BOOL
VAR_INPUT
    (* Candidate queue slot (stored verbatim for the plan) *)
    iIdx  : SINT;
    (* Candidate item record (capture frame pose used) *)
    stIt  : ST_SP_TrkItem;
END_VAR
VAR
    (* Cup loop index (best-match scan) *)
    c  : SINT;
    (* Member loop index (gap rule) *)
    k  : SINT;
    (* Best cup found (0 = none) and its distance [mm] *)
    iBestC : SINT;
rBest  : LREAL;                        (* Best assignment score found so far (lower = better) *)
    (* Required world position of cup c *)
    rReqX, rReqY : LREAL;
    (* Cup offset relative to the anchor cup (tool frame) *)
    rDX, rDY : LREAL;
    (* Candidate-to-required distance [mm] *)
    rD : LREAL;
    (* Candidate-to-member distance [mm] (gap rule) *)
    rG : LREAL;
    (* TRUE when all rules passed for the current cup *)
    bOkC : BOOL;
END_VAR
    OfferCand := FALSE;
    IF NOT m_bRun THEN
        RETURN;
    END_IF
    IF m_uiN >= m_stReq.uiCups THEN
        RETURN;                 (* Head already full *)
    END_IF

    (* Rule 1: product type *)
    IF m_stReq.bSingleType AND (stIt.uiTypeId <> m_uiTypeA) THEN
        RETURN;
    END_IF

    (* Rule 2: payload capacity (unknown weights count as zero) *)
    IF (m_stReq.rMaxWeight > 0.0) AND (stIt.rWeight > 0.0) THEN
        IF (m_rW + stIt.rWeight) > m_stReq.rMaxWeight THEN
            RETURN;
        END_IF
    END_IF

    (* Rule 3: minimum gap to every accepted member *)
    IF m_stReq.rMinGap > 0.0 THEN
        FOR k := 1 TO UINT_TO_DINT(m_uiN) DO
            rG := SQRT( (stIt.p2World.rX - m_astP[k].rX) * (stIt.p2World.rX - m_astP[k].rX)
                      + (stIt.p2World.rY - m_astP[k].rY) * (stIt.p2World.rY - m_astP[k].rY) );
            IF rG < m_stReq.rMinGap THEN
                RETURN;         (* Too close to an accepted item *)
            END_IF
        END_FOR
    END_IF

    (* Rule 4: geometric match to an unassigned cup *)
    iBestC := 0;
    rBest  := m_stReq.rMatchTol + 1.0E9;
    FOR c := 2 TO UINT_TO_DINT(m_stReq.uiCups) DO
        IF NOT m_abCupUsed[c] THEN
            (* Required world position of this cup for the candidate *)
            rDX := m_stReq.astCup[c].rX - m_stReq.astCup[1].rX;
            rDY := m_stReq.astCup[c].rY - m_stReq.astCup[1].rY;
            rReqX := m_p2A.rX + FUN_SP_RotX(m_p2A.rTh, rDX, rDY);
            rReqY := m_p2A.rY + FUN_SP_RotY(m_p2A.rTh, rDX, rDY);
            rD := SQRT( (stIt.p2World.rX - rReqX) * (stIt.p2World.rX - rReqX)
                      + (stIt.p2World.rY - rReqY) * (stIt.p2World.rY - rReqY) );
            IF rD <= m_stReq.rMatchTol THEN
                bOkC := TRUE;
                (* Gap rule also against the cup position itself *)
                IF rD < rBest THEN
                    rBest  := rD;
                    iBestC := c;
                END_IF
            END_IF
        END_IF
    END_FOR

    IF iBestC = 0 THEN
        RETURN;                 (* No cup within tolerance *)
    END_IF

    (* Accept the candidate on the best cup *)
    m_uiN := m_uiN + UINT#1;
    m_aiIdx[m_uiN] := iIdx;
    m_aCup[m_uiN]  := iBestC;
    m_abCupUsed[iBestC] := TRUE;
    m_astP[m_uiN].rX  := stIt.p2World.rX;
    m_astP[m_uiN].rY  := stIt.p2World.rY;
    m_astP[m_uiN].rZ  := stIt.rZWorld;
    m_astP[m_uiN].rTh := stIt.p2World.rTh;
    m_arW[m_uiN] := stIt.rWeight;
    m_rW := m_rW + stIt.rWeight;
    OfferCand := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Finish (parent SP_GripPlanner)
   Close the session: fit the synchronized TCP pose, prune outliers,
   run the CoG audit and publish the final plan.
   ----------------------------------------------------------------------- *)
METHOD Finish : ET_SP_RetCode
VAR
    (* Member loop index (fit / prune / compact) *)
    i, k : SINT;
    (* Working cup array reordered per member (residual input) *)
    astCw : ARRAY[1..GC_CUPS] OF ST_SP_Point3D;
    (* Fitted TCP yaw and translation accumulators *)
    rYaw, rTx, rTy : LREAL;
    (* Worst residual of the current fit [mm] *)
    rRes : LREAL;
    (* Index and value of the worst member (pruning) *)
    iWorst : SINT;
rWorst : LREAL;                        (* Largest per-cup residual of the candidate set [mm] *)
    (* Per-member residual (pruning scan) *)
    rD : LREAL;
    (* Center-of-gravity accumulators *)
    rCogX, rCogY : LREAL;
    (* Weight sum as LREAL (type-safe division) *)
    rWL : LREAL;
    (* Prune loop guard *)
    iGuard : SINT;
END_VAR
    Finish := ET_SP_RetCode#ErrState;
    IF NOT m_bRun THEN
        RETURN;
    END_IF
    m_bRun := FALSE;

    (* Publish the raw member set *)
    out_uiN := m_uiN;
    out_rW  := m_rW;
    out_bOk := TRUE;
    FOR i := 1 TO GC_CUPS DO
        out_aiIdx[i] := m_aiIdx[i];
        out_aCup[i]  := m_aCup[i];
        out_astP[i]  := m_astP[i];
    END_FOR

    (* ------------------- Single member: trivial plan ------------------- *)
    IF m_uiN <= UINT#1 THEN
        out_bSync := FALSE;
        out_uiN   := UINT#1;
        out_stTcp := m_astP[1];
        out_rCog  := 0.0;
        Finish := ET_SP_RetCode#Done;
        RETURN;
    END_IF

    (* ------------- Least-squares TCP fit + tolerance pruning ----------- *)
    (* Bounded loop: every pruning pass removes one member, so at most
       GC_CUPS + 1 fits are ever computed. *)
    rRes := GC_REAL_MAX;
    FOR iGuard := 1 TO (GC_CUPS + 1) DO
        (* Reorder the cup array per member for the residual function *)
        FOR i := 1 TO UINT_TO_DINT(m_uiN) DO
            astCw[i] := m_stReq.astCup[m_aCup[i]];
        END_FOR

        (* Fit: yaw = circular mean, XY = least-squares translation *)
        rYaw := FUN_SP_FitYaw(m_astP, m_uiN);
        rTx := 0.0; rTy := 0.0;
        FOR i := 1 TO UINT_TO_DINT(m_uiN) DO
            rTx := rTx + m_astP[i].rX - FUN_SP_RotX(rYaw, astCw[i].rX, astCw[i].rY);
            rTy := rTy + m_astP[i].rY - FUN_SP_RotY(rYaw, astCw[i].rX, astCw[i].rY);
        END_FOR
        rTx := rTx / UDINT_TO_LREAL(UINT_TO_UDINT(m_uiN));
        rTy := rTy / UDINT_TO_LREAL(UINT_TO_UDINT(m_uiN));
        out_stTcp.rX  := rTx;
        out_stTcp.rY  := rTy;
        out_stTcp.rZ  := m_astP[1].rZ;
        out_stTcp.rTh := rYaw;

        rRes := FUN_SP_ClusterResidual(m_astP, astCw, out_stTcp, m_uiN);
        IF rRes <= m_stReq.rMatchTol THEN
            EXIT;               (* Whole cluster within tolerance *)
        END_IF
        IF m_uiN <= UINT#1 THEN
            EXIT;               (* Only the anchor left: stop pruning *)
        END_IF

        (* Drop the worst non-anchor member and refit *)
        iWorst := 0;
        rWorst := -1.0;
        FOR i := 2 TO UINT_TO_DINT(m_uiN) DO
            rD := SQRT( (out_stTcp.rX + FUN_SP_RotX(rYaw, astCw[i].rX, astCw[i].rY) - m_astP[i].rX)
                      * (out_stTcp.rX + FUN_SP_RotX(rYaw, astCw[i].rX, astCw[i].rY) - m_astP[i].rX)
                      + (out_stTcp.rY + FUN_SP_RotY(rYaw, astCw[i].rX, astCw[i].rY) - m_astP[i].rY)
                      * (out_stTcp.rY + FUN_SP_RotY(rYaw, astCw[i].rX, astCw[i].rY) - m_astP[i].rY) );
            IF rD > rWorst THEN
                rWorst := rD;
                iWorst := i;
            END_IF
        END_FOR
        IF iWorst = 0 THEN
            EXIT;               (* Defensive: nothing to drop *)
        END_IF
        FOR k := iWorst TO (UINT_TO_DINT(m_uiN) - 1) DO
            m_aiIdx[k] := m_aiIdx[k + 1];
            m_aCup[k]  := m_aCup[k + 1];
            m_astP[k]  := m_astP[k + 1];
            m_arW[k]   := m_arW[k + 1];
        END_FOR
        m_uiN := m_uiN - UINT#1;
    END_FOR

    out_uiN := m_uiN;
    out_bSync := (m_uiN >= UINT#2) AND (rRes <= m_stReq.rMatchTol);

    (* ------------------------- CoG audit -------------------------------- *)
    out_rCog := 0.0;
    IF (m_stReq.rMaxCog > 0.0) AND (m_rW > 0.0) AND out_bSync THEN
        rCogX := 0.0; rCogY := 0.0;
        FOR i := 1 TO UINT_TO_DINT(m_uiN) DO
            rCogX := rCogX + m_arW[i] * (m_astP[i].rX - out_stTcp.rX);
            rCogY := rCogY + m_arW[i] * (m_astP[i].rY - out_stTcp.rY);
        END_FOR
        rWL := REAL_TO_LREAL(m_rW);
        IF rWL > 0.0 THEN
            rCogX := rCogX / rWL;
            rCogY := rCogY / rWL;
            out_rCog := SQRT(rCogX * rCogX + rCogY * rCogY);
            IF out_rCog > m_stReq.rMaxCog THEN
                (* Unstable load: degrade to a safe single pick of the anchor *)
                out_bSync := FALSE;
                out_uiN   := UINT#1;
                out_stTcp := m_astP[1];
                out_rCog  := 0.0;
            END_IF
        END_IF
    END_IF

    Finish := ET_SP_RetCode#Done;
END_METHOD
