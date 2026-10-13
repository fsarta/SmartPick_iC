(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 05_Tracking
   Worksheet : FB - SP_ItemQueue
   -----------------------------------------------------------------------------
   Purpose   : Ring-buffer queue of tracked items for one feed.
               Array of STRUCT (never array of FB). All selection logic is
               implemented in methods using only VAR/VAR_INPUT.

   Selection policy (cut-off reservation, MotoPick 4 style):
     - Candidates: state = Tracked, inside the tracking window, inside the
       requesting robot work range (along-belt offset), type/weight filters.
     - Winner: nearest to the pick line (smallest upstream offset) ->
       maximizes window usage and throughput.
   -----------------------------------------------------------------------------
   Housekeeping purges: picked/lost slots, timed-out items, items that
   passed the pick line without reservation (window exit).
   =============================================================================
*)

FUNCTION_BLOCK SP_ItemQueue
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    uiTracked  : UINT;          (* Items in state Tracked *)
    uiReserved : UINT;          (* Items in state Reserved *)
    out_stItem : ST_SP_TrkItem; (* Result buffer of GetItem *)
    out_rNear  : LREAL;         (* Result buffer of NearDist [mm] *)
    out_stRes  : ST_SP_ResRsp;  (* Result buffer of Reserve *)
    out_stCl   : ST_SP_ClRsp;   (* Result buffer of ReserveCluster (R-07) *)
    out_uiPurged : UINT;        (* Result buffer of Housekeeping (total) *)
    out_uiPurgedFlow : UINT;    (* Housekeeping: lost/timed-out items *)
    out_uiPurgedTerm : UINT;    (* Housekeeping: closed picks/placements *)
    out_bDup   : BOOL;          (* TRUE when Add merged/suppressed a duplicate item *)
END_VAR
VAR
    (* Ring of tracked items (fixed slots, bValid = occupancy, 1..GC_QUEUE) *)
    m_astQ   : ARRAY[1..64] OF ST_SP_TrkItem;
    m_iFree  : SINT := 0;       (* Free slot count *)
    m_stCfg  : ST_SP_TrkCfg;    (* Feed tracking config (copy) *)
    m_bCfgOk : BOOL;
    (* Multi-grip cluster planner (R-07, pull API, module 13) *)
    m_Plan   : SP_GripPlanner;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
THIS.PublishCounts();
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: PublishCounts (parent SP_ItemQueue) - internal
   Recompute the published counters (single pass).
   ----------------------------------------------------------------------- *)
METHOD PublishCounts : BOOL
VAR
    (* Slot loop index (aging) *)
    i : SINT;
    (* Tracked-state counter *)
    uiT : UINT;
    (* Reserved-state counter *)
    uiR : UINT;
    (* Free-slot counter *)
    iF : SINT;
END_VAR
    PublishCounts := TRUE;          (* Counters recomputed *)
    uiT := 0; uiR := 0; iF := 0;
    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid THEN
            CASE m_astQ[i].eState OF
                ET_SP_ItemState#Tracked:  uiT := uiT + 1;
                ET_SP_ItemState#Reserved: uiR := uiR + 1;
                ELSE (* counted as free-able when purged by housekeeping *)
            END_CASE
        ELSE
            iF := iF + 1;
        END_IF
    END_FOR
    uiTracked  := uiT;
    uiReserved := uiR;
    m_iFree    := iF;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_ItemQueue)
   Store the feed tracking configuration used by selection and prediction.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Feed tracking configuration (direction, window, timeout) *)
    stIn : ST_SP_TrkCfg;
END_VAR
    IF (stIn.iDir <> 1) AND (stIn.iDir <> -1) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    m_stCfg  := stIn;
    m_bCfgOk := TRUE;
    Configure := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FindDuplicate (parent SP_ItemQueue) - internal helper
   Search the queue for an existing physical item (Tracked, Reserved or
   Picked) that matches stItem on the belt surface at stItem.rEncCap
   within the configured overlap tolerance rDupTol [mm].
   Returns the matching slot index (1..GC_QUEUE) or 0 when stItem is new.
   ----------------------------------------------------------------------- *)
METHOD FindDuplicate : SINT
VAR_INPUT
    (* Newly detected item in feed/world coordinates *)
    stItem : ST_SP_TrkItem;
END_VAR
VAR
    (* Slot loop index *)
    i      : SINT;
    (* Best matching slot so far (0 = none) *)
    iBest  : SINT;
    (* Effective duplicate suppression tolerance [mm] *)
    rTol   : LREAL;
    (* Best Euclidean distance on belt [mm] *)
    rBestD : LREAL;
    (* Projected along-belt offset of existing item at stItem.rEncCap [mm] *)
    rVOld  : LREAL;
    (* Belt-plane deltas (across belt u, along belt v) and distance [mm] *)
    rDu    : LREAL;
    rDv    : LREAL;
    rDist  : LREAL;
    (* Type match flag *)
    bTypeOk: BOOL;
END_VAR
    FindDuplicate := 0;
    IF stItem.bTarget OR (NOT m_bCfgOk) THEN
        RETURN;
    END_IF

    IF m_stCfg.rDupTol > 0.0 THEN
        rTol := m_stCfg.rDupTol;
    ELSE
        rTol := GC_DUP_TOL_MM;
    END_IF

    iBest  := 0;
    rBestD := rTol;
    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid AND (NOT m_astQ[i].bTarget) THEN
            IF (m_astQ[i].eState = ET_SP_ItemState#Tracked)
               OR (m_astQ[i].eState = ET_SP_ItemState#Reserved)
               OR (m_astQ[i].eState = ET_SP_ItemState#Picked) THEN
                bTypeOk := (NOT m_stCfg.bDupSameType)
                           OR (m_astQ[i].uiTypeId = UINT#0)
                           OR (stItem.uiTypeId = UINT#0)
                           OR (m_astQ[i].uiTypeId = stItem.uiTypeId);
                IF bTypeOk THEN
                    rVOld := THIS.ItemOffset(m_astQ[i], stItem.rEncCap);
                    rDu   := stItem.rCrossCap - m_astQ[i].rCrossCap;
                    rDv   := stItem.rBeltCap - rVOld;
                    rDist := SQRT(rDu * rDu + rDv * rDv);
                    IF rDist <= rBestD THEN
                        rBestD := rDist;
                        iBest  := i;
                    END_IF
                END_IF
            END_IF
        END_IF
    END_FOR
    FindDuplicate := iBest;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Add (parent SP_ItemQueue)
   Deduplicate against existing belt items first (multi-photo overlap):
     - If the same physical part is already Tracked, refine its pose and
       encoder stamp in place (compensates belt slip using the fresher
       shot closer to the pick line).
     - If the same physical part is already Reserved or Picked, suppress
       the duplicate detection so no second robot attempts to pick it.
     - Otherwise, store the new tracked item in the first free slot.
   ----------------------------------------------------------------------- *)
METHOD Add : ET_SP_RetCode
VAR_INPUT
    (* Item to insert *)
    stItem : ST_SP_TrkItem;
END_VAR
VAR
    (* Slot loop index / duplicate slot index *)
    i    : SINT;
    iDup : SINT;
END_VAR
    out_bDup := FALSE;
    iDup := THIS.FindDuplicate(stItem);
    IF iDup > 0 THEN
        out_bDup := TRUE;
        IF m_astQ[iDup].eState = ET_SP_ItemState#Tracked THEN
            (* Refine the unreserved item with the fresher camera observation *)
            m_astQ[iDup].rCrossCap := stItem.rCrossCap;
            m_astQ[iDup].rBeltCap  := stItem.rBeltCap;
            m_astQ[iDup].rEncCap   := stItem.rEncCap;
            m_astQ[iDup].p2World   := stItem.p2World;
            m_astQ[iDup].rZWorld   := stItem.rZWorld;
            m_astQ[iDup].tAgeMs    := UDINT#0;
            IF stItem.rScore >= m_astQ[iDup].rScore THEN
                m_astQ[iDup].uiTypeId := stItem.uiTypeId;
                m_astQ[iDup].rScore   := stItem.rScore;
                IF stItem.rWeight > 0.0 THEN
                    m_astQ[iDup].rWeight := stItem.rWeight;
                END_IF
            END_IF
        END_IF
        (* When Reserved or Picked, keep the existing slot untouched and
           suppress the duplicate detection *)
        Add := ET_SP_RetCode#Done;
        RETURN;
    END_IF

    Add := ET_SP_RetCode#ErrFull;
    FOR i := 1 TO GC_QUEUE DO
        IF NOT m_astQ[i].bValid THEN
            m_astQ[i] := stItem;
            m_astQ[i].bValid := TRUE;
            Add := ET_SP_RetCode#Done;
            THIS.PublishCounts();
            EXIT;
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ItemOffset (parent SP_ItemQueue) - internal pure helper
   Current upstream offset of item iIdx given the present encoder value:
   v_now = rBeltCap - iDir * (rEncNow - rEncCap)
   (iDir = +1: increasing encoder coordinate moves toward the pick line).
   ----------------------------------------------------------------------- *)
METHOD ItemOffset : LREAL
VAR_INPUT
    (* Item whose offset is queried *)
    stIt    : ST_SP_TrkItem;
    (* Current belt encoder [mm] *)
    rEncNow : LREAL;
END_VAR
    ItemOffset := stIt.rBeltCap - SINT_TO_LREAL(m_stCfg.iDir) * (rEncNow - stIt.rEncCap);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Reserve (parent SP_ItemQueue)
   Cut-off reservation of the best candidate for the requesting robot.
   Result: out_stRes (item snapshot + predicted pick pose + belt speed).
   ----------------------------------------------------------------------- *)
METHOD Reserve : ET_SP_RetCode
VAR_INPUT
    stReq    : ST_SP_ResReq;   (* Robot, range, filters *)
    rEncNow  : LREAL;          (* Current belt encoder [mm] *)
    rBeltSpd : LREAL;          (* Current signed belt speed [mm/s] *)
END_VAR
VAR
    (* Slot of the best (nearest) candidate (0 = none) *)
    iBest: SINT;
    (* Best candidate offset [mm] *)
    rBest: LREAL;
    (* Slot loop index (aging) *)
    i    : SINT;
    (* Candidate offset upstream of the pick line [mm] *)
    rOff : LREAL;
    (* Working copy of the candidate record *)
    stC  : ST_SP_TrkItem;
    (* Remaining travel to the pick line [mm] *)
    rD   : LREAL;
    (* Item motion direction in world [deg] *)
    rAng : LREAL;
END_VAR
    out_stRes.bOk := FALSE;
    Reserve := ET_SP_RetCode#ErrEmpty;

    IF NOT m_bCfgOk THEN
        Reserve := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF

    (* 1) Find the nearest candidate meeting all filters *)
    iBest := 0;
    rBest := GC_REAL_MAX;
    FOR i := 1 TO GC_QUEUE DO
        stC := m_astQ[i];
        IF stC.bValid AND (stC.eState = ET_SP_ItemState#Tracked) THEN
            (* Type filter (0 = any) *)
            IF (stReq.uiTypeId = 0) OR (stReq.uiTypeId = stC.uiTypeId) THEN
                (* Target filter *)
                IF (NOT stReq.bTargetOnly) OR stC.bTarget THEN
                    (* Weight filter (0 = unlimited) *)
                    IF (stReq.rMaxWeight <= 0.0) OR (stC.rWeight <= 0.0)
                       OR (stC.rWeight <= stReq.rMaxWeight) THEN
                        rOff := THIS.ItemOffset(stC, rEncNow);
                        (* Window + robot work range (along-belt) *)
                        IF (rOff >= 0.0) AND (rOff <= (m_stCfg.rWinStart + m_stCfg.rWinLen))
                           AND (rOff >= stReq.rRangeFrom) AND (rOff <= stReq.rRangeTo) THEN
                            IF rOff < rBest THEN
                                rBest := rOff;
                                iBest := i;
                            END_IF
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_IF
    END_FOR

    IF iBest = 0 THEN
        RETURN;                     (* No candidate *)
    END_IF

    (* 2) Commit the reservation *)
    stC := m_astQ[iBest];
    stC.eState := ET_SP_ItemState#Reserved;
    stC.iReservedBy := stReq.iRobotId;
    m_astQ[iBest] := stC;

    (* 3) Predict the pick pose on the pick line (cut-off prediction)
       Item motion direction in world = stWorld.rRot - 90 deg (decreasing v).
       stC.p2World is the capture world pose at v = stC.rBeltCap, so shifting
       by stC.rBeltCap along the belt direction projects onto v = 0 (pick line). *)
    rOff := THIS.ItemOffset(stC, rEncNow);
    rAng := m_stCfg.stWorld.rRot - GC_90;      (* [deg] *)
    rD   := stC.rBeltCap;   (* Travel from capture pose to pick line [mm] *)

    out_stRes.bOk  := TRUE;
    out_stRes.iIdx := iBest;
    out_stRes.stItem := stC;
    out_stRes.rBeltSpd := rBeltSpd;
    out_stRes.p3Pick.rX  := stC.p2World.rX + rD * COS(rAng * GC_DEG2RAD);
    out_stRes.p3Pick.rY  := stC.p2World.rY + rD * SIN(rAng * GC_DEG2RAD);
    out_stRes.p3Pick.rZ  := stC.rZWorld;
    out_stRes.p3Pick.rTh := stC.p2World.rTh;

    THIS.PublishCounts();
    Reserve := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ReserveCluster (parent SP_ItemQueue) - R-07 advanced multi-grip
   Cut-off reservation of a whole geometrically compatible cluster.

   Semantics: the ANCHOR is the front candidate (smallest upstream offset,
   identical selection rules as Reserve). The synchronized pick event is
   "anchor at the pick line"; at that instant every member has translated
   rigidly by the anchor travel (belt rigidity), so:
     - candidate matching runs on the CAPTURE world poses (invariant), and
     - the published per-member pick poses and the synchronized TCP pose
       are the capture poses shifted by the anchor travel.
   Candidates ahead of the anchor are never accepted (they would be past
   the pick line at the event), which also keeps every member inside the
   tracking window until the event (no housekeeping purge risk).

   The cluster intelligence (cup assignment, tolerance pruning, payload
   and CoG rules) lives in SP_GripPlanner; this method owns storage,
   candidate enumeration and reservation commit.
   ----------------------------------------------------------------------- *)
METHOD ReserveCluster : ET_SP_RetCode
VAR_INPUT
    (* Cluster request: tool geometry + rules (from the robot cfg) *)
    stCl     : ST_SP_ClReq;
    (* Current belt encoder [mm] *)
    rEncNow  : LREAL;
    (* Current signed belt speed [mm/s] *)
    rBeltSpd : LREAL;
END_VAR
VAR
    (* Slot loop index (enumeration / commit) *)
    i    : SINT;
    (* Selection pass index (bounded enumeration) *)
    iPass : SINT;
    (* Ordered candidate list (front-to-rear) *)
    uiOrd  : UINT;
    aiOrd  : ARRAY[1..64] OF SINT;   (* Cluster pick order (queue indices, front to rear) *)
    aOff   : ARRAY[1..64] OF LREAL;  (* Per-ordered-item belt offset for the rigid prediction [mm] *)
    abDone : ARRAY[1..64] OF BOOL;   (* TRUE once the item index is committed to the cluster *)
    (* Anchor slot, capture encoder and upstream offset (cluster travel) *)
    iAnchor  : SINT;
    rOffA    : LREAL;                      (* Belt offset of the anchor item (cluster reference) [mm] *)
    rEncCapA : LREAL;                      (* Capture encoder of the anchor item [mm] *)
    rDltSync : LREAL;                      (* Encoder travel between anchor shot and candidate shot [mm] *)
    (* Candidate scan working data *)
    stC      : ST_SP_TrkItem;
    stCSync  : ST_SP_TrkItem;              (* Candidate synchronized to the anchor capture encoder *)
    rOff     : LREAL;                      (* Belt offset of the candidate relative to the anchor [mm] *)
    (* Belt motion direction unit vector in world *)
    rAng, rDx, rDy : LREAL;
    (* Selection-scan helpers *)
    iSel    : SINT;
rSel    : LREAL;                       (* Best residual score so far (lower = better fit) *)
    (* Planner call results *)
    bTake   : BOOL;
eRc     : ET_SP_RetCode;               (* Cluster reservation result accumulator *)
    (* Commit loop index *)
    k    : SINT;
iS   : SINT;                           (* Ordered-slot scan index *)
END_VAR
    out_stCl.bOk := FALSE;
    out_stCl.bSync := FALSE;
    out_stCl.uiN := UINT#0;
    ReserveCluster := ET_SP_RetCode#ErrEmpty;

    IF NOT m_bCfgOk THEN
        ReserveCluster := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF

    (* 1) Front-to-rear enumeration of the admissible candidates -------- *)
    FOR i := 1 TO GC_QUEUE DO
        abDone[i] := FALSE;
        aiOrd[i]  := 0;
        aOff[i]   := 0.0;
    END_FOR
    uiOrd := UINT#0;
    FOR iPass := 1 TO GC_QUEUE DO
        iSel := 0;
        rSel := GC_REAL_MAX;
        FOR i := 1 TO GC_QUEUE DO
            IF (NOT abDone[i]) AND m_astQ[i].bValid THEN
                stC := m_astQ[i];
                IF (stC.eState = ET_SP_ItemState#Tracked)
                   AND (NOT stC.bTarget)
                   AND ((stCl.uiTypeId = UINT#0) OR (stCl.uiTypeId = stC.uiTypeId))
                   AND ((stCl.rMaxWeight <= 0.0) OR (stC.rWeight <= 0.0)
                        OR (stC.rWeight <= stCl.rMaxWeight)) THEN
                    rOff := THIS.ItemOffset(stC, rEncNow);
                    IF (rOff >= 0.0) AND (rOff <= (m_stCfg.rWinStart + m_stCfg.rWinLen))
                       AND (rOff >= stCl.rRangeFrom) AND (rOff <= stCl.rRangeTo) THEN
                        IF rOff < rSel THEN
                            rSel := rOff;
                            iSel := i;
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_FOR
        IF iSel = 0 THEN
            EXIT;               (* Enumeration complete *)
        END_IF
        abDone[iSel] := TRUE;
        uiOrd := uiOrd + UINT#1;
        aiOrd[UINT_TO_DINT(uiOrd)] := iSel;
        aOff[UINT_TO_DINT(uiOrd)] := rSel;
    END_FOR

    IF uiOrd = UINT#0 THEN
        RETURN;                 (* No candidate at all *)
    END_IF

    (* 2) Open the planner session on the anchor (front candidate) ------- *)
    rAng := m_stCfg.stWorld.rRot - GC_90;   (* [deg] *)
    rDx  := COS(rAng * GC_DEG2RAD);
    rDy  := SIN(rAng * GC_DEG2RAD);
    iAnchor  := aiOrd[1];
    stC      := m_astQ[iAnchor];
    rOffA    := stC.rBeltCap;
    rEncCapA := stC.rEncCap;
    eRc := m_Plan.Begin(stCl, stC.p2World, stC.uiTypeId, stC.rZWorld, stC.rWeight);
    IF eRc <> ET_SP_RetCode#Done THEN
        ReserveCluster := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF

    (* 3) Offer the remaining candidates front-to-rear (aligned to anchor shot) *)
    FOR k := 2 TO UINT_TO_SINT(uiOrd) DO
        stC      := m_astQ[aiOrd[k]];
        stCSync  := stC;
        rDltSync := SINT_TO_LREAL(m_stCfg.iDir) * (stC.rEncCap - rEncCapA);
        stCSync.p2World.rX := stC.p2World.rX - rDltSync * rDx;
        stCSync.p2World.rY := stC.p2World.rY - rDltSync * rDy;
        bTake := m_Plan.OfferCand(aiOrd[k], stCSync);
        (* The queue keeps unaccepted candidates tracked: no action *)
    END_FOR

    eRc := m_Plan.Finish();
    IF eRc <> ET_SP_RetCode#Done THEN
        ReserveCluster := ET_SP_RetCode#ErrState;
        RETURN;
    END_IF

    (* 4) Commit: reserve the final plan members -------------------------- *)
    out_stCl.uiN := m_Plan.out_uiN;
    FOR k := 1 TO UINT_TO_SINT(m_Plan.out_uiN) DO
        IF k = 1 THEN
            iS := iAnchor;      (* Anchor slot known by the queue *)
        ELSE
            iS := m_Plan.out_aiIdx[k];
        END_IF
        IF (iS >= 1) AND (iS <= GC_QUEUE) THEN
            stC := m_astQ[iS];
            IF stC.bValid AND (stC.eState = ET_SP_ItemState#Tracked) THEN
                stC.eState := ET_SP_ItemState#Reserved;
                stC.iReservedBy := stCl.iRobotId;
                m_astQ[iS] := stC;
            END_IF

            (* Rigid translation of the capture pose to the instant when
               the anchor reaches the pick line (compensated for shot delta) *)
            rDltSync := SINT_TO_LREAL(m_stCfg.iDir) * (stC.rEncCap - rEncCapA);
            out_stCl.aiIdx[k] := iS;
            out_stCl.aCup[k]  := m_Plan.out_aCup[k];
            out_stCl.astRsp[k].bOk := TRUE;
            out_stCl.astRsp[k].iIdx := iS;
            out_stCl.astRsp[k].stItem := stC;
            out_stCl.astRsp[k].p3Pick.rX  := stC.p2World.rX + (rOffA - rDltSync) * rDx;
            out_stCl.astRsp[k].p3Pick.rY  := stC.p2World.rY + (rOffA - rDltSync) * rDy;
            out_stCl.astRsp[k].p3Pick.rZ  := stC.rZWorld;
            out_stCl.astRsp[k].p3Pick.rTh := stC.p2World.rTh;
            out_stCl.astRsp[k].rBeltSpd := rBeltSpd;
        END_IF
    END_FOR

    (* 5) Publish the synchronized TCP pose (same rigid translation) ----- *)
    out_stCl.bOk   := TRUE;
    out_stCl.bSync := m_Plan.out_bSync;
    out_stCl.stTcp := m_Plan.out_stTcp;
    out_stCl.stTcp.rX := m_Plan.out_stTcp.rX + rOffA * rDx;
    out_stCl.stTcp.rY := m_Plan.out_stTcp.rY + rOffA * rDy;
    out_stCl.rTotWeight := m_Plan.out_rW;
    out_stCl.rCogOff := m_Plan.out_rCog;

    THIS.PublishCounts();
    ReserveCluster := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Release (parent SP_ItemQueue)
   Undo a reservation (robot abort / pause policy). Reserved -> Tracked.
   ----------------------------------------------------------------------- *)
METHOD Release : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to release *)
    iIdx : SINT;
END_VAR
    Release := ET_SP_RetCode#ErrNotFound;
    IF (iIdx >= 1) AND (iIdx <= GC_QUEUE) THEN
        IF m_astQ[iIdx].bValid AND (m_astQ[iIdx].eState = ET_SP_ItemState#Reserved) THEN
            m_astQ[iIdx].eState := ET_SP_ItemState#Tracked;
            m_astQ[iIdx].iReservedBy := GC_ID_NONE;
            Release := ET_SP_RetCode#Done;
            THIS.PublishCounts();
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompletePick (parent SP_ItemQueue)
   Close a pick attempt. bOk = grip verified: item leaves the belt flow
   (Picked, purged by housekeeping). bOk = FALSE: retry policy - item
   returns to Tracked until uiAttempts reaches the retry limit.
   ----------------------------------------------------------------------- *)
METHOD CompletePick : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to close *)
    iIdx     : SINT;
    (* TRUE = grip verified (pick succeeded) *)
    bOk      : BOOL;
    (* Retry limit before the item is declared Lost *)
    uiMaxTry : UINT;
END_VAR
    CompletePick := ET_SP_RetCode#ErrNotFound;
    IF (iIdx >= 1) AND (iIdx <= GC_QUEUE) THEN
        IF m_astQ[iIdx].bValid AND (m_astQ[iIdx].eState = ET_SP_ItemState#Reserved) THEN
            IF bOk THEN
                m_astQ[iIdx].eState := ET_SP_ItemState#Picked;
            ELSE
                m_astQ[iIdx].uiAttempts := m_astQ[iIdx].uiAttempts + 1;
                IF m_astQ[iIdx].uiAttempts >= uiMaxTry THEN
                    m_astQ[iIdx].eState := ET_SP_ItemState#Lost;
                ELSE
                    m_astQ[iIdx].eState := ET_SP_ItemState#Tracked;
                END_IF
            END_IF
            m_astQ[iIdx].iReservedBy := GC_ID_NONE;
            CompletePick := ET_SP_RetCode#Done;
            THIS.PublishCounts();
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetItem (parent SP_ItemQueue)
   Copy item iIdx into out_stItem. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD GetItem : BOOL
VAR_INPUT
    (* Queue slot to copy *)
    iIdx : SINT;
END_VAR
    GetItem := FALSE;
    IF (iIdx >= 1) AND (iIdx <= GC_QUEUE) THEN
        IF m_astQ[iIdx].bValid THEN
            out_stItem := m_astQ[iIdx];
            GetItem := TRUE;
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SetPlaced (parent SP_ItemQueue)
   Mark a target as placed (target flow bookkeeping).
   ----------------------------------------------------------------------- *)
METHOD SetPlaced : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to mark placed *)
    iIdx : SINT;
END_VAR
    SetPlaced := ET_SP_RetCode#ErrNotFound;
    IF (iIdx >= 1) AND (iIdx <= GC_QUEUE) THEN
        IF m_astQ[iIdx].bValid THEN
            m_astQ[iIdx].eState := ET_SP_ItemState#Placed;
            SetPlaced := ET_SP_RetCode#Done;
            THIS.PublishCounts();
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: NearDist (parent SP_ItemQueue)
   Distance of the nearest flow item (Tracked or Reserved) upstream of the
   pick line -> drives the conveyor slow & stop arbitration. TRUE when an
   item exists (out_rNear = distance); FALSE when empty (out_rNear = max).
   ----------------------------------------------------------------------- *)
METHOD NearDist : BOOL
VAR_INPUT
    (* Current belt encoder [mm] *)
    rEncNow : LREAL;
END_VAR
VAR
    (* Slot loop index (aging) *)
    i    : SINT;
    (* Item offset re-read for prediction *)
    rOff : LREAL;
    (* Nearest upstream distance [mm] *)
    rBest: LREAL;
END_VAR
    rBest := GC_REAL_MAX;
    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid THEN
            IF (m_astQ[i].eState = ET_SP_ItemState#Tracked)
               OR (m_astQ[i].eState = ET_SP_ItemState#Reserved) THEN
                rOff := THIS.ItemOffset(m_astQ[i], rEncNow);
                IF (rOff >= 0.0) AND (rOff < rBest) THEN
                    rBest := rOff;
                END_IF
            END_IF
        END_IF
    END_FOR
    out_rNear := rBest;
    NearDist := (rBest < GC_REAL_MAX);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Housekeeping (parent SP_ItemQueue)
   Periodic maintenance: purge terminal states (Picked/Placed/Lost/
   TimedOut), enforce the tracking timeout on aged items, drop items that
   exited the window behind the pick line. Purged count in out_uiPurged.
   ----------------------------------------------------------------------- *)
METHOD Housekeeping : ET_SP_RetCode
VAR_INPUT
    rEncNow : LREAL;    (* Current belt encoder [mm] *)
END_VAR
VAR
    (* Slot loop index (aging) *)
    i      : SINT;
    (* Item offset re-read for prediction *)
    rOff   : LREAL;
    (* Total purged records this call *)
    uiPurge: UINT;
    (* Purged flow records (Lost/TimedOut) *)
    uiFlow : UINT;
    (* Purged terminal records (Picked/Placed) *)
    uiTerm : UINT;
    (* Tracking timeout in ms (from config) *)
    uiToMs : UDINT;
END_VAR
    uiPurge := 0;
    uiFlow  := 0;
    uiTerm  := 0;
    uiToMs  := TIME_TO_UDINT(m_stCfg.tTimeout);

    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid THEN
            CASE m_astQ[i].eState OF
                ET_SP_ItemState#Picked,
                ET_SP_ItemState#Placed:
                    m_astQ[i].bValid := FALSE;      (* Closed flow records *)
                    uiPurge := uiPurge + 1;
                    uiTerm  := uiTerm + 1;

                ET_SP_ItemState#Lost,
                ET_SP_ItemState#TimedOut:
                    m_astQ[i].bValid := FALSE;
                    uiPurge := uiPurge + 1;
                    uiFlow  := uiFlow + 1;

                ET_SP_ItemState#Tracked:
                    rOff := THIS.ItemOffset(m_astQ[i], rEncNow);
                    IF (m_stCfg.tTimeout > T#0S) AND (m_astQ[i].tAgeMs > uiToMs) THEN
                        m_astQ[i].eState := ET_SP_ItemState#TimedOut;  (* Aged out *)
                    ELSIF rOff < -GC_WIN_BEHIND THEN
                        m_astQ[i].eState := ET_SP_ItemState#Lost;  (* Window exit *)
                    END_IF

                ELSE
                    (* Reserved: owned by a robot, aging handled by robot *)
            END_CASE
        END_IF
    END_FOR

    out_uiPurged := uiPurge;
    out_uiPurgedFlow := uiFlow;
    out_uiPurgedTerm := uiTerm;
    THIS.PublishCounts();
    Housekeeping := ET_SP_RetCode#Done;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AgeItems (parent SP_ItemQueue)
   Advance the age of live items by the task period (called once per cycle
   by the feed manager before housekeeping).
   ----------------------------------------------------------------------- *)
METHOD AgeItems : BOOL
VAR_INPUT
    uiDtMs : UDINT;     (* Task period [ms] *)
END_VAR
VAR
    (* Slot loop index (aging) *)
    i : SINT;
END_VAR
    AgeItems := TRUE;               (* Aging pass executed *)
    IF uiDtMs = 0 THEN
        RETURN;
    END_IF
    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid THEN
            IF (m_astQ[i].eState = ET_SP_ItemState#Tracked)
               OR (m_astQ[i].eState = ET_SP_ItemState#Reserved) THEN
                m_astQ[i].tAgeMs := m_astQ[i].tAgeMs + uiDtMs;
            END_IF
        END_IF
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearAll (parent SP_ItemQueue)
   Drop every item (recipe change / resiliency reset).
   ----------------------------------------------------------------------- *)
METHOD ClearAll : UINT
VAR
    (* Slot loop index (aging) *)
    i : SINT;
END_VAR
    ClearAll := UINT#0;
    FOR i := 1 TO GC_QUEUE DO
        IF m_astQ[i].bValid THEN
            ClearAll := ClearAll + UINT#1;   (* Dropped item count *)
        END_IF
        m_astQ[i].bValid := FALSE;
        m_astQ[i].eState := ET_SP_ItemState#Free;
    END_FOR
    THIS.PublishCounts();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddRaw (parent SP_ItemQueue)
   Direct insert of a prepared item record (used for placement targets
   generated by the pattern engine).
   ----------------------------------------------------------------------- *)
METHOD AddRaw : ET_SP_RetCode
VAR_INPUT
    (* Prepared record inserted directly *)
    stItem : ST_SP_TrkItem;
END_VAR
    AddRaw := THIS.Add(stItem);
END_METHOD
