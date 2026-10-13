(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 05_Tracking
   Worksheet : FB - SP_TrkFeed
   -----------------------------------------------------------------------------
   Purpose   : Per-feed tracking manager (one tracked conveyor segment).

   Frame pipeline:
     camera(u,v) --astCalib[iCam]--> feed(u,v)  u = across belt [mm]
                                                v = upstream of pick line [mm]
     feed(u,v)   --stWorld------->  world(X,Y,th) robot base frame

   Responsibilities:
     - Ingest vision items (FeedItem) and generated targets (AddTarget)
     - Cut-off reservations for robots (Reserve -> out_stRes)
     - Pick closing with retry policy (CompletePick), target bookkeeping
     - Item aging, housekeeping and purge statistics
     - Nearest-item distance for the conveyor slow & stop arbitration
   -----------------------------------------------------------------------------
   Pause/resume: encoder-based tracking means a pause loses nothing; on
   resume the same items keep valid offsets (MotoPick 4 parity).
   =============================================================================
*)

FUNCTION_BLOCK SP_TrkFeed
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    stOut     : ST_SP_TrkStat;    (* Published statistics *)
    out_stRes : ST_SP_ResRsp;     (* Reservation result buffer *)
    out_stCl  : ST_SP_ClRsp;      (* Cluster reservation result buffer (R-07) *)
    out_rNear : LREAL;            (* Nearest item distance [mm] *)
    bNearFound: BOOL;             (* TRUE when an item is in flow *)
END_VAR
VAR
    stCfg   : ST_SP_TrkCfg;       (* Feed configuration *)
    m_bCfgOk: BOOL;
    m_Q     : SP_ItemQueue;       (* Item ring buffer *)
    m_udiLost: UDINT := 0;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
stOut.uiTracked  := m_Q.uiTracked;
stOut.uiReserved := m_Q.uiReserved;
stOut.udiLost    := m_udiLost;
stOut.bWindowBusy := (m_Q.uiTracked + m_Q.uiReserved) >= UDINT_TO_UINT(SINT_TO_UDINT(GC_QUEUE) - 2);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_TrkFeed)
   Validate and distribute the feed configuration (queue included).
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Feed configuration (frames, window, direction) *)
    stIn : ST_SP_TrkCfg;
END_VAR
    Configure := ET_SP_RetCode#Done;

    IF (stIn.iDir <> 1) AND (stIn.iDir <> -1) THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    IF stIn.rWinLen <= 0.0 THEN
        Configure := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF

    stCfg := stIn;
    m_bCfgOk := TRUE;
    Configure := m_Q.Configure(stIn);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FeedItem (parent SP_TrkFeed)
   Ingest a vision item detected by camera iCam: transform to feed and
   world frames, store in the queue with the capture encoder stamp.
   ----------------------------------------------------------------------- *)
METHOD FeedItem : ET_SP_RetCode
VAR_INPUT
    stVi : ST_SP_VisionItem;    (* Item in camera frame *)
    iCam : SINT;                (* Detecting camera 1..GC_CAMS *)
END_VAR
VAR
    (* Item record assembled from the vision result *)
    stNew : ST_SP_TrkItem;
    (* Item position mapped into the feed frame *)
    rU, rV: LREAL;
    (* Calibration transform camera -> feed frame *)
    stCal : ST_SP_Transf2D;
END_VAR
    FeedItem := ET_SP_RetCode#ErrState;
    IF NOT m_bCfgOk THEN
        RETURN;
    END_IF
    IF (iCam < 1) OR (iCam > GC_CAMS) THEN
        FeedItem := ET_SP_RetCode#ErrParam;
        RETURN;
    END_IF
    stCal := stCfg.astCalib[iCam];
    IF NOT stCal.bValid THEN
        FeedItem := ET_SP_RetCode#ErrState;   (* Camera not calibrated *)
        RETURN;
    END_IF

    (* Camera -> feed frame (u = across belt, v = upstream offset) *)
    rU := FUN_SP_TrfX(stCal, stVi.p2.rX, stVi.p2.rY);
    rV := FUN_SP_TrfY(stCal, stVi.p2.rX, stVi.p2.rY);
    IF rV < 0.0 THEN
        FeedItem := ET_SP_RetCode#ErrRange;   (* Behind pick line at capture *)
        RETURN;
    END_IF

    (* Build the tracked record *)
    stNew.udiId     := stVi.udiId;
    stNew.uiTypeId  := stVi.uiTypeId;
    stNew.rCrossCap := rU;
    stNew.rBeltCap  := rV;
    stNew.rEncCap   := stVi.rBeltPos;
    stNew.p2World.rX  := FUN_SP_TrfX(stCfg.stWorld, rU, rV);
    stNew.p2World.rY  := FUN_SP_TrfY(stCfg.stWorld, rU, rV);
    stNew.p2World.rTh := FUN_SP_NormAng(stCal.rRot + stCfg.stWorld.rRot + stVi.p2.rTh);
    stNew.rZWorld := stCfg.rZBelt;
    stNew.rWeight := stVi.rWeight;
    stNew.rScore  := stVi.rScore;
    stNew.eState  := ET_SP_ItemState#Tracked;
    stNew.iReservedBy := GC_ID_NONE;
    stNew.uiAttempts  := UINT#0;
    stNew.bTarget  := FALSE;
    stNew.udiBatchId := UDINT#0;
    stNew.uiSlot := UINT#0;
    stNew.tAgeMs := UDINT#0;

    FeedItem := m_Q.Add(stNew);
    IF FeedItem = ET_SP_RetCode#Done THEN
        IF m_Q.out_bDup THEN
            stOut.udiDup := stOut.udiDup + UDINT#1;
        ELSE
            stOut.udiFed := stOut.udiFed + UDINT#1;
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddTarget (parent SP_TrkFeed)
   Insert a placement target generated by the pattern engine. The target
   record arrives already in feed/world coordinates.
   ----------------------------------------------------------------------- *)
METHOD AddTarget : ET_SP_RetCode
VAR_INPUT
    stTarget : ST_SP_TrkItem;   (* Prepared target record *)
END_VAR
    AddTarget := ET_SP_RetCode#ErrState;
    IF NOT m_bCfgOk THEN
        RETURN;
    END_IF
    AddTarget := m_Q.AddRaw(stTarget);
    IF AddTarget = ET_SP_RetCode#Done THEN
        stOut.udiFed := stOut.udiFed + 1;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Reserve (parent SP_TrkFeed)
   Cut-off reservation for a robot. Result copied to out_stRes.
   ----------------------------------------------------------------------- *)
METHOD Reserve : ET_SP_RetCode
VAR_INPUT
    (* Reservation request (robot, range, filters) *)
    stReq    : ST_SP_ResReq;
    (* Current belt encoder [mm] (housekeeping) *)
    rEncNow  : LREAL;
    (* Current signed belt speed [mm/s] *)
    rBeltSpd : LREAL;
END_VAR
VAR
    (* Queue Reserve() result *)
    eRc : ET_SP_RetCode;
END_VAR
    eRc := m_Q.Reserve(stReq, rEncNow, rBeltSpd);
    out_stRes := m_Q.out_stRes;
    Reserve := eRc;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ReserveCluster (parent SP_TrkFeed) - R-07 multi-grip
   Cluster cut-off reservation (see SP_ItemQueue.ReserveCluster for the
   full semantics). Result copied to out_stCl.
   ----------------------------------------------------------------------- *)
METHOD ReserveCluster : ET_SP_RetCode
VAR_INPUT
    (* Cluster request: tool geometry + rules *)
    stCl     : ST_SP_ClReq;
    (* Current belt encoder [mm] *)
    rEncNow  : LREAL;
    (* Current signed belt speed [mm/s] *)
    rBeltSpd : LREAL;
END_VAR
VAR
    (* Queue ReserveCluster() result *)
    eRc : ET_SP_RetCode;
END_VAR
    eRc := m_Q.ReserveCluster(stCl, rEncNow, rBeltSpd);
    out_stCl := m_Q.out_stCl;
    ReserveCluster := eRc;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CompletePick (parent SP_TrkFeed)
   Close a pick attempt with the retry policy (uiMaxTry from robot config).
   ----------------------------------------------------------------------- *)
METHOD CompletePick : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to release *)
    iIdx     : SINT;
    (* Grip verification result forwarded to the queue *)
    bOk      : BOOL;
    (* Retry limit forwarded to the queue *)
    uiMaxTry : UINT;
END_VAR
VAR
    (* Queue CompletePick() result *)
    eRc : ET_SP_RetCode;
END_VAR
    eRc := m_Q.CompletePick(iIdx, bOk, uiMaxTry);
    IF (eRc = ET_SP_RetCode#Done) AND bOk THEN
        stOut.udiPicked := stOut.udiPicked + 1;
    END_IF
    CompletePick := eRc;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Release (parent SP_TrkFeed) - undo a reservation.
   ----------------------------------------------------------------------- *)
METHOD Release : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to mark placed *)
    iIdx : SINT;
END_VAR
    Release := m_Q.Release(iIdx);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: PlaceTarget (parent SP_TrkFeed)
   Confirm a target placement (target bookkeeping on outfeed queues).
   ----------------------------------------------------------------------- *)
METHOD PlaceTarget : ET_SP_RetCode
VAR_INPUT
    (* Queue slot to mark placed *)
    iIdx : SINT;
END_VAR
    PlaceTarget := m_Q.SetPlaced(iIdx);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: NearDist (parent SP_TrkFeed)
   Nearest flow item distance upstream of the pick line (conveyor input).
   ----------------------------------------------------------------------- *)
METHOD NearDist : BOOL
VAR_INPUT
    (* Current belt encoder [mm] (housekeeping) *)
    rEncNow : LREAL;
END_VAR
    bNearFound := m_Q.NearDist(rEncNow);
    out_rNear  := m_Q.out_rNear;
    NearDist := bNearFound;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Housekeeping (parent SP_TrkFeed)
   Age items, then purge terminal/aged/off-window records.
   ----------------------------------------------------------------------- *)
METHOD Housekeeping : BOOL
VAR_INPUT
    (* Current belt encoder [mm] (housekeeping) *)
    rEncNow : LREAL;
    (* Task period [ms] for item aging *)
    uiDtMs  : UDINT;
END_VAR
    Housekeeping := TRUE;           (* Aging + purge executed *)
    m_Q.AgeItems(uiDtMs);
    m_Q.Housekeeping(rEncNow);
    (* Lost/timed-out purges feed the loss counter (MotoPick 4 telemetry) *)
    m_udiLost := m_udiLost + UINT_TO_UDINT(m_Q.out_uiPurgedFlow);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ResetAll (parent SP_TrkFeed)
   Drop all items (batch change, resiliency recovery, recipe load).
   ----------------------------------------------------------------------- *)
METHOD ResetAll : BOOL
    ResetAll := TRUE;               (* Queue dropped *)
    m_Q.ClearAll();
    stOut.uiTracked := 0;
    stOut.uiReserved := 0;
END_METHOD
