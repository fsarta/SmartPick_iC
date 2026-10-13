(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 07_LoadSharing
   Worksheet : FB - SP_LoadBalancer
   -----------------------------------------------------------------------------
   Purpose   : Automatic item distribution among robots (MotoPick 4 parity):

     Strategies (per feed, configurable):
       Organic  - first eligible robot in rank order (strict priority when
                  cfg.bStrictOrder, ring rotation otherwise).
       Greedy   - robot with the least estimated time: cartesian distance
                  to the item plus a queue-depth penalty.
       Balanced - weighted round robin: least (jobs + 1) / share ratio.
       Manual   - fixed feed x robot allow matrix.

     Cross-cutting rules:
       - Eligibility: online, no fault, tool available, work range match
         (per robot x feed), type restriction via 32-bit mask (UDINT).
       - Match modes: Matched (type restrictions enforced), Unmatched
         (any robot, bulk picking), Mixed (masked robots first).
       - User defined share ratios (Balanced) and robot specific work
         ranges are honored by every strategy.
   -----------------------------------------------------------------------------
   The balancer is purely combinational: no firmware calls, no I/O.
   =============================================================================
*)

FUNCTION_BLOCK SP_LoadBalancer
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    out_rBestScore : LREAL;     (* Score of the chosen robot (diagnostic) *)
    out_iEligible  : SINT;      (* Number of eligible robots (diagnostic) *)
END_VAR
VAR
    (* Strategy table, ratios, type masks and work ranges *)
    m_stCfg  : ST_SP_ShareCfg;
    (* TRUE after a valid Configure() *)
    m_bCfgOk : BOOL;
    m_iRing  : SINT := 0;       (* Organic ring rotation state *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Combinational FB: everything is method driven. *)
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_LoadBalancer)
   Validate and store the distribution configuration (ratios sanitized).
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Configuration to store (ratios sanitized) *)
    stIn : ST_SP_ShareCfg;
END_VAR
VAR
    (* Robot loop index *)
    i : SINT;
END_VAR
    m_stCfg := stIn;
    FOR i := 1 TO GC_ROBOTS DO
        IF stIn.arRatio[i] <= 0.0 THEN
            m_stCfg.arRatio[i] := 1.0;
        END_IF
    END_FOR
    m_bCfgOk := TRUE;
    Configure := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Eligible (parent SP_LoadBalancer) - internal
   TRUE when the robot may take the offer: online, no fault, idle, tool
   free, work range match and (optionally) type mask match.
   ----------------------------------------------------------------------- *)
METHOD Eligible : BOOL
VAR_INPUT
    (* Candidate robot snapshot *)
    stRob   : ST_SP_RobShare;
    (* Offer to assign (Manual pass) *)
    stOffer : ST_SP_Offer;
    bCheckType : BOOL;      (* FALSE disables the type mask (Unmatched) *)
END_VAR
VAR
    (* Type bit built from the offer type id *)
    udBit : UDINT;
    (* Bit position (typeId - 1, clamped 0..31) *)
    uiShift : UDINT;
    (* Type-mask eligibility result *)
    bTypeOk : BOOL;
END_VAR
    Eligible := FALSE;

    IF (NOT stRob.bOnline) OR stRob.bFault OR (NOT stRob.bIdle) THEN
        RETURN;
    END_IF
    IF stRob.uiToolMask = UINT#0 THEN
        RETURN;                     (* No free tool *)
    END_IF

    (* Work range on the along-belt offset (robot specific) *)
    IF (stOffer.rBeltOff < m_stCfg.arRangeFrom[stOffer.iFeed][stRob.iRobotId])
       OR (stOffer.rBeltOff > m_stCfg.arRangeTo[stOffer.iFeed][stRob.iRobotId]) THEN
        RETURN;
    END_IF

    (* Type restriction (32-bit mask, bit i-1 = type i) *)
    bTypeOk := TRUE;
    IF bCheckType AND (stOffer.uiTypeId > UINT#0) THEN
        uiShift := UINT_TO_UDINT(stOffer.uiTypeId) - UDINT#1;
        IF uiShift > UDINT#31 THEN
            uiShift := UDINT#31;    (* Mask domain guard *)
        END_IF
        udBit := SHL(UDINT#1, uiShift);
        bTypeOk := (m_stCfg.audTypeMask[stRob.iRobotId] AND udBit) <> UDINT#0;
    END_IF

    Eligible := bTypeOk;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OfferProduct (parent SP_LoadBalancer)
   Assign an item offer to a robot. Returns the robot id (1..GC_ROBOTS)
   or 0 when no robot is eligible. Strategy selected per feed.
   ----------------------------------------------------------------------- *)
METHOD OfferProduct : SINT
VAR_INPUT
    (* Offer to assign (Manual pass) *)
    stOffer : ST_SP_Offer;
    (* Live robot snapshot array *)
    astRob  : ARRAY[1..GC_ROBOTS] OF ST_SP_RobShare;
END_VAR
VAR
    (* Strategy configured for the feed *)
    eStrat : ET_SP_ShareStrategy;
    (* Robot id returned by the helper (0 = none) *)
    iRes   : SINT;
    (* TRUE on pass 2: ignore the type mask (Mixed fallback) *)
    bTryAny: BOOL;
    (* Pass counter (1 = strict, 2 = fallback) *)
    iPass  : SINT;
END_VAR
    out_iEligible := 0;
    out_rBestScore := GC_REAL_MAX;
    OfferProduct := GC_ID_NONE;

    IF NOT m_bCfgOk THEN
        RETURN;
    END_IF
    IF (stOffer.iFeed < 1) OR (stOffer.iFeed > GC_FEEDS) THEN
        RETURN;
    END_IF

    eStrat := m_stCfg.aeStrat[stOffer.iFeed];
    bTryAny := FALSE;

    (* Two passes for Mixed mode: 1 = with type mask, 2 = without *)
    FOR iPass := 1 TO 2 DO
        CASE eStrat OF
            ET_SP_ShareStrategy#Organic:
                iRes := THIS.m_Organic(stOffer, astRob, bTryAny);
            ET_SP_ShareStrategy#Greedy:
                iRes := THIS.m_Greedy(stOffer, astRob, bTryAny);
            ET_SP_ShareStrategy#Balanced:
                iRes := THIS.m_Balanced(stOffer, astRob, bTryAny);
            ELSE
                iRes := THIS.m_Manual(stOffer, astRob, bTryAny);
        END_CASE

        IF iRes > 0 THEN
            OfferProduct := iRes;
            RETURN;
        END_IF

        (* Mixed mode fallback: second pass ignores the type mask *)
        IF m_stCfg.eMatch <> ET_SP_MatchMode#Mixed THEN
            EXIT;
        END_IF
        bTryAny := TRUE;
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_Organic (parent SP_LoadBalancer) - internal
   Ring/priority scan: strict order or rotating ring start.
   ----------------------------------------------------------------------- *)
METHOD m_Organic : SINT
VAR_INPUT
    (* Offer to assign (Manual pass) *)
    stOffer  : ST_SP_Offer;
    (* Live robot snapshot array *)
    astRob   : ARRAY[1..GC_ROBOTS] OF ST_SP_RobShare;
    (* Type-mask bypass flag (fallback pass) *)
    bTryAny  : BOOL;
END_VAR
VAR
    (* Greedy scan indices (iStart = rotation anchor) *)
    i, iK, iStart : SINT;
    (* Robot id returned by the helper (0 = none) *)
    iRes : SINT;
END_VAR
    iRes := GC_ID_NONE;
    IF m_stCfg.bStrictOrder THEN
        iStart := 1;
    ELSE
        m_iRing := m_iRing + 1;
        IF m_iRing > GC_ROBOTS THEN
            m_iRing := 1;
        END_IF
        iStart := m_iRing;
    END_IF

    FOR iK := 0 TO (GC_ROBOTS - 1) DO
        i := iStart + iK;
        IF i > GC_ROBOTS THEN
            i := i - GC_ROBOTS;
        END_IF
        IF THIS.Eligible(astRob[i], stOffer, NOT bTryAny) THEN
            out_iEligible := out_iEligible + 1;
            IF iRes = GC_ID_NONE THEN
                iRes := astRob[i].iRobotId;
            END_IF
        END_IF
    END_FOR
    m_Organic := iRes;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_Greedy (parent SP_LoadBalancer) - internal
   Least estimated time: distance to the item + queue penalty.
   ----------------------------------------------------------------------- *)
METHOD m_Greedy : SINT
VAR_INPUT
    (* Offer to assign (Manual pass) *)
    stOffer  : ST_SP_Offer;
    (* Live robot snapshot array *)
    astRob   : ARRAY[1..GC_ROBOTS] OF ST_SP_RobShare;
    (* Type-mask bypass flag (fallback pass) *)
    bTryAny  : BOOL;
END_VAR
VAR
    (* Robot loop index *)
    i : SINT;
    (* Normalized cost and best cost so far *)
    rCost, rBest : LREAL;
    (* Robot id returned by the helper (0 = none) *)
    iRes : SINT;
END_VAR
    iRes := GC_ID_NONE;
    rBest := GC_REAL_MAX;
    FOR i := 1 TO GC_ROBOTS DO
        IF THIS.Eligible(astRob[i], stOffer, NOT bTryAny) THEN
            out_iEligible := out_iEligible + 1;
            rCost := FUN_SP_Dist2D(astRob[i].p2Now.rX, astRob[i].p2Now.rY,
                                   stOffer.stW.rX, stOffer.stW.rY)
                     + astRob[i].rLoadPct * 1000.0;   (* Queue penalty [mm eq.] *)
            IF rCost < rBest THEN
                rBest := rCost;
                iRes  := astRob[i].iRobotId;
            END_IF
        END_IF
    END_FOR
    out_rBestScore := rBest;
    m_Greedy := iRes;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_Balanced (parent SP_LoadBalancer) - internal
   Weighted round robin by user share ratios.
   ----------------------------------------------------------------------- *)
METHOD m_Balanced : SINT
VAR_INPUT
    (* Offer to assign (Manual pass) *)
    stOffer  : ST_SP_Offer;
    (* Live robot snapshot array *)
    astRob   : ARRAY[1..GC_ROBOTS] OF ST_SP_RobShare;
    (* Type-mask bypass flag (fallback pass) *)
    bTryAny  : BOOL;
END_VAR
VAR
    (* Robot loop index *)
    i : SINT;
    (* Share-ratio score and best score so far *)
    rScore, rBest : LREAL;
    (* Robot id returned by the helper (0 = none) *)
    iRes : SINT;
END_VAR
    iRes := GC_ID_NONE;
    rBest := GC_REAL_MAX;
    FOR i := 1 TO GC_ROBOTS DO
        IF THIS.Eligible(astRob[i], stOffer, NOT bTryAny) THEN
            out_iEligible := out_iEligible + 1;
            rScore := UDINT_TO_LREAL(astRob[i].udiPicks + astRob[i].udiPlaces + UDINT#1)
                      / m_stCfg.arRatio[astRob[i].iRobotId];
            IF rScore < rBest THEN
                rBest := rScore;
                iRes  := astRob[i].iRobotId;
            END_IF
        END_IF
    END_FOR
    out_rBestScore := rBest;
    m_Balanced := iRes;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_Manual (parent SP_LoadBalancer) - internal
   Fixed allow matrix feed x robot, lowest robot id first.
   ----------------------------------------------------------------------- *)
METHOD m_Manual : SINT
VAR_INPUT
    (* Offer to assign (Manual pass) *)
    stOffer  : ST_SP_Offer;
    (* Live robot snapshot array *)
    astRob   : ARRAY[1..GC_ROBOTS] OF ST_SP_RobShare;
    (* Type-mask bypass flag (fallback pass) *)
    bTryAny  : BOOL;
END_VAR
VAR
    (* Robot loop index *)
    i : SINT;
    (* Robot id returned by the helper (0 = none) *)
    iRes : SINT;
END_VAR
    iRes := GC_ID_NONE;
    FOR i := 1 TO GC_ROBOTS DO
        IF m_stCfg.aabManual[stOffer.iFeed][i] THEN
            IF THIS.Eligible(astRob[i], stOffer, NOT bTryAny) THEN
                out_iEligible := out_iEligible + 1;
                IF iRes = GC_ID_NONE THEN
                    iRes := astRob[i].iRobotId;
                END_IF
            END_IF
        END_IF
    END_FOR
    m_Manual := iRes;
END_METHOD
