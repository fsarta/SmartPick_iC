(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 09_Production
   Worksheet : FB - SP_Dispatch
   -----------------------------------------------------------------------------
   Purpose   : Job dispatcher: couples the load balancer with the tracking
               queues and the robots (asynchronous multi pick & place of up
               to GC_CUPS parts per cycle).

   Assignment direction: per feed, the balancer chooses the best robot for
   the nearest item (strategy per feed: organic/greedy/balanced/manual).
   The chosen robot starts (or continues) a job: pick reservation on the
   feed, then a type-matched target reservation on the mapped outfeed,
   repeated until the multi-grip count is reached or the queues starve.

   Handshake (no FB references: all through public members, single-writer):
     Dispatcher.astReq[r]  + abReqPulse[r]  -> PRG performs feed.Reserve
     PRG writes astResRsp[r] + abResDone[r] -> Dispatcher continues
     Dispatcher.ajobOffer[r] + abJobPulse[r] -> PRG applies rob.OfferJob
     PRG writes astJobRes[r] + abJobResDone[r] -> Dispatcher idle again
     Dispatcher.astCancel[r] + abCancelPulse[r] -> PRG releases (feed.Release)

   Since v1.6 the executing program may live in a DIFFERENT task than the
   dispatcher (PRG_SP_TaskFast executes, PRG_SP_TaskMain runs Run()).
   Therefore the request flags are LATCHED: Run() only SETS them; the
   executing program clears abReqPulse/abJobPulse/abCancelPulse together
   with its response. No request can be lost by scan order, and no request
   is executed twice (the executor consumes it exactly once).

   Dispatch states per robot: 1=Idle 2=ReqPick 3=WaitPick 4=ReqPlace
   5=WaitPlace 6=Offer 7=WaitJob
   =============================================================================
*)

FUNCTION_BLOCK SP_Dispatch
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    (* Public configuration (Main writes) *)
    stShare  : ST_SP_ShareCfg;          (* Distribution configuration *)
    aiOutfeed: ARRAY[1..8] OF SINT;     (* mirror of stShare.aiOutfeedMap 1..GC_FEEDS *)
    abiFeedOn: ARRAY[1..8] OF BOOL;     (* Feed eligible for dispatch 1..GC_FEEDS *)
    bEnable  : BOOL;                    (* System dispatch gate *)
    uiMaxGrip: UINT := UINT#1;          (* Parts per cycle *)
    (* R-07: synchronized multi-grip enabled per robot (Main fills from
       the robot cfg: eGripMode = Sync AND uiMaxGrip > 1) 1..GC_ROBOTS *)
    abSyncGrip : ARRAY[1..4] OF BOOL;
    (* Handshake responses and latched request flags (Main/Fast access) 1..GC_ROBOTS *)
    astReq   : ARRAY[1..4] OF ST_SP_DispReq;
    abReqPulse : ARRAY[1..4] OF BOOL;
    astResRsp  : ARRAY[1..4] OF ST_SP_ResRsp;   (* Fast fills *)
    abResDone  : ARRAY[1..4] OF BOOL;           (* Fast fills *)
    astClRsp   : ARRAY[1..4] OF ST_SP_ClRsp;    (* Fast fills *)
    ajobOffer  : ARRAY[1..4] OF ST_SP_Job;      (* Completed job offers per robot *)
    abJobPulse : ARRAY[1..4] OF BOOL;
    astJobRes  : ARRAY[1..4] OF ST_SP_Job;      (* Fast fills *)
    abJobResDone : ARRAY[1..4] OF BOOL;         (* Fast fills *)
    astCancel  : ARRAY[1..4] OF ST_SP_CancelReq;
    abCancelPulse: ARRAY[1..4] OF BOOL;
END_VAR
VAR
    (* Subordinate load balancer *)
    Bal : SP_LoadBalancer;
    (* Per-robot dispatch state 1..GC_ROBOTS *)
    m_aeDSt : ARRAY[1..4] OF SINT;
    (* Job under construction per robot 1..GC_ROBOTS *)
    m_astJob : ARRAY[1..4] OF ST_SP_Job;
    (* Pick feed of the assigned offer 1..GC_ROBOTS *)
    m_iPickFeed : ARRAY[1..4] OF SINT;
    (* Place (out)feed derived from the batch 1..GC_ROBOTS *)
    m_iPlaceFeed: ARRAY[1..4] OF SINT;
    (* Tool id allocated for the job 1..GC_ROBOTS *)
    m_uiTool : ARRAY[1..4] OF UINT;
    m_astShare : ARRAY[1..4] OF ST_SP_RobShare; (* Snapshot cache 1..GC_ROBOTS *)
    (* R-07: request was a cluster reservation (latched for the response) *)
    m_abClReq : ARRAY[1..4] OF BOOL;
    (* R-07: job under construction is a cluster job (slot place flow) *)
    m_abClJob : ARRAY[1..4] OF BOOL;
    (* R-07: job slot whose place target is being reserved *)
    m_iPlaceSlot : ARRAY[1..4] OF SINT;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
THIS.Run();
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_Dispatch)
   Configure the internal load balancer and store the distribution config.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Load sharing configuration *)
    stIn : ST_SP_ShareCfg;
END_VAR
    stShare := stIn;
    aiOutfeed := stIn.aiOutfeedMap;
    Configure := Bal.Configure(stIn);
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Run (parent SP_Dispatch) - internal
   Cyclic step: refresh the balancer snapshot, assign feeds to idle
   robots through the balancer, then advance every robot handshake.
   ----------------------------------------------------------------------- *)
METHOD Run : BOOL
VAR
    (* Robot and general loop indices *)
    i, k : SINT;
    (* Offer assembled for the balancer *)
    stOffer : ST_SP_Offer;
    (* Robot id returned by the balancer (0 = none) *)
    iRobot  : SINT;
END_VAR
    Run := TRUE;                    (* Cyclic step executed *)
    (* 0) Snapshot the robot mirror for the balancer *)
    FOR i := 1 TO GC_ROBOTS DO
        m_astShare[i].iRobotId := i;
        m_astShare[i].bOnline := g_astRobStat[i].bOnline;
        m_astShare[i].bFault := g_astRobStat[i].bFault;
        m_astShare[i].bIdle := g_astRobStat[i].bReady;
        m_astShare[i].uiToolMask := g_astRobStat[i].uiToolMask;
        m_astShare[i].rLoadPct := g_astRobStat[i].rLoadPct;
        m_astShare[i].udiPicks := g_astRobStat[i].udiPicks;
        m_astShare[i].udiPlaces := g_astRobStat[i].udiPlaces;
        m_astShare[i].p2Now := g_astRobStat[i].p2Now;
        (* NOTE: abReqPulse / abJobPulse / abCancelPulse are NOT cleared
           here - they stay latched until the executing program consumes
           them (multi-task safe, see header). *)
    END_FOR

    (* 1) Feed-driven assignments (balancer strategy per feed) *)
    IF bEnable THEN
        FOR k := 1 TO GC_FEEDS DO
            IF abiFeedOn[k] AND g_astFeedIo[k].bUsed
               AND (NOT g_astFeedIo[k].bIsOutfeed)
               AND (g_astFeedIo[k].stStat.uiTracked > UINT#0) THEN
                stOffer.iFeed := k;
                stOffer.uiTypeId := UINT#0;      (* Any type, mask filtered *)
                stOffer.rBeltOff := g_astFeedIo[k].rNearOff;
                stOffer.stW := g_astFeedIo[k].stPickLineW;
                stOffer.bTarget := FALSE;

                iRobot := Bal.OfferProduct(stOffer, m_astShare);
                IF (iRobot >= 1) AND (iRobot <= GC_ROBOTS) THEN
                    IF m_aeDSt[iRobot] = 1 THEN
                        m_iPickFeed[iRobot] := k;
                        m_astJob[iRobot].eKind := ET_SP_JobKind#PickPlace;
                        m_astJob[iRobot].iRobot := iRobot;
                        m_astJob[iRobot].uiCount := UINT#0;
                        m_uiTool[iRobot] := UINT#1;
                        m_aeDSt[iRobot] := 2;
                    END_IF
                END_IF
            END_IF
        END_FOR
    END_IF

    (* 2) Per-robot handshake machines *)
    FOR i := 1 TO GC_ROBOTS DO
        THIS.StepRobot(i);
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StepRobot (parent SP_Dispatch) - internal
   Reservation/job handshake of one robot.
   ----------------------------------------------------------------------- *)
METHOD StepRobot : BOOL
VAR_INPUT
    (* Robot whose item is being stored *)
    iR : SINT;
END_VAR
VAR
    (* Reservation request read from the robot mirror *)
    stReq : ST_SP_DispReq;
    (* Reservation response carrying the pick pose *)
    stRsp : ST_SP_ResRsp;
    (* Job item position being filled *)
    uiCnt : UINT;
    (* Type id of the reserved item *)
    uiType: UINT;
    (* Cluster member loop index (R-07) *)
    k : SINT;
END_VAR
    StepRobot := TRUE;              (* Handshake step executed *)
    CASE m_aeDSt[iR] OF
        1: (* DIdle: nothing to do; assignment arrives from Run() *)
            IF (NOT bEnable) THEN
                (* stay idle *)
            END_IF

        2: (* DReqPick *)
            uiCnt := m_astJob[iR].uiCount;
            IF uiCnt >= uiMaxGrip THEN
                m_aeDSt[iR] := 6;           (* Full: offer the job *)
            ELSIF NOT bEnable THEN
                THIS.Abandon(iR);           (* System stopping *)
            ELSIF abSyncGrip[iR] AND (uiCnt = UINT#0) THEN
                (* R-07: synchronized multi-grip - reserve the whole
                   cluster in one call. Tool 1 is the cluster head; the
                   cluster payload (stCl) is filled by Main from the tool
                   configuration (geometry lives there). *)
                m_uiTool[iR] := UINT#1;
                stReq.bReq := TRUE;
                stReq.iFeed := m_iPickFeed[iR];
                stReq.uiTypeId := UINT#0;
                stReq.bTargetOnly := FALSE;
                stReq.rMaxWeight := 0.0;
                stReq.bCluster := TRUE;
                stReq.stCl.iRobotId := iR;
                stReq.stCl.rRangeFrom := 0.0;   (* Main sets the work range *)
                stReq.stCl.rRangeTo := 0.0;
                stReq.stCl.uiTypeId := UINT#0;
                stReq.stCl.rMaxWeight := 0.0;
                astReq[iR] := stReq;
                abReqPulse[iR] := TRUE;
                m_abClReq[iR] := TRUE;
                m_aeDSt[iR] := 3;
            ELSE
                stReq.bReq := TRUE;
                stReq.iFeed := m_iPickFeed[iR];
                stReq.uiTypeId := UINT#0;
                stReq.bTargetOnly := FALSE;
                stReq.rMaxWeight := 0.0;
                stReq.bCluster := FALSE;
                astReq[iR] := stReq;
                abReqPulse[iR] := TRUE;
                m_abClReq[iR] := FALSE;
                m_aeDSt[iR] := 3;
            END_IF

        3: (* DWaitPick *)
            IF abResDone[iR] THEN
                abResDone[iR] := FALSE;
                IF m_abClReq[iR] THEN
                    (* R-07: cluster response - store all members at once *)
                    IF astClRsp[iR].bOk THEN
                        m_astJob[iR].uiCount := astClRsp[iR].uiN;
                        FOR k := 1 TO UINT_TO_SINT(astClRsp[iR].uiN) DO
                            THIS.StoreItem(iR, DINT_TO_UINT(SINT_TO_DINT(k)),
                                           astClRsp[iR].astRsp[k], TRUE,
                                           astClRsp[iR].aCup[k]);
                        END_FOR
                        IF astClRsp[iR].bSync THEN
                            m_astJob[iR].eExec := ET_SP_GripExec#SyncAll;
                            m_astJob[iR].stSyncPick := astClRsp[iR].stTcp;
                        ELSE
                            m_astJob[iR].eExec := ET_SP_GripExec#AsyncCup;
                        END_IF
                        m_abClJob[iR] := TRUE;
                        m_iPlaceSlot[iR] := 1;
                        (* Target reservation on the mapped outfeed *)
                        m_iPlaceFeed[iR] := aiOutfeed[m_iPickFeed[iR]];
                        IF (m_iPlaceFeed[iR] >= 1) AND (m_iPlaceFeed[iR] <= GC_FEEDS) THEN
                            m_aeDSt[iR] := 4;
                        ELSE
                            m_aeDSt[iR] := 6;   (* Pick-only cluster *)
                        END_IF
                    ELSE
                        m_abClReq[iR] := FALSE;
                        m_aeDSt[iR] := 1;       (* Starved: retry next offer *)
                    END_IF
                ELSE
                    stRsp := astResRsp[iR];
                    IF stRsp.bOk THEN
                        uiCnt := m_astJob[iR].uiCount + UINT#1;
                        m_astJob[iR].uiCount := uiCnt;
                        THIS.StoreItem(iR, uiCnt, stRsp, TRUE, -1);
                        m_astJob[iR].eExec := ET_SP_GripExec#AsyncCup;
                        (* Target reservation on the mapped outfeed *)
                        m_iPlaceFeed[iR] := aiOutfeed[m_iPickFeed[iR]];
                        IF (m_iPlaceFeed[iR] >= 1) AND (m_iPlaceFeed[iR] <= GC_FEEDS) THEN
                            m_aeDSt[iR] := 4;
                        ELSE
                            m_aeDSt[iR] := 2;   (* Pick-only item *)
                        END_IF
                    ELSE
                        (* Queue starved: offer what we have (if any) *)
                        IF m_astJob[iR].uiCount >= UINT#1 THEN
                            m_aeDSt[iR] := 6;
                        ELSE
                            m_aeDSt[iR] := 1;
                        END_IF
                    END_IF
                END_IF
            END_IF

        4: (* DReqPlace: type-matched target from the outfeed.
              Legacy path: slot = uiCount (current cup). Cluster path:
              slot = m_iPlaceSlot (iterates the stored members). *)
            IF m_abClJob[iR] THEN
                uiCnt := DINT_TO_UINT(SINT_TO_DINT(m_iPlaceSlot[iR]));
            ELSE
                uiCnt := m_astJob[iR].uiCount;
            END_IF
            uiType := m_astJob[iR].astItems[uiCnt].stItem.uiTypeId;
            stReq.bReq := TRUE;
            stReq.iFeed := m_iPlaceFeed[iR];
            stReq.uiTypeId := uiType;
            stReq.bTargetOnly := TRUE;
            stReq.rMaxWeight := 0.0;
            stReq.bCluster := FALSE;
            astReq[iR] := stReq;
            abReqPulse[iR] := TRUE;
            m_aeDSt[iR] := 5;

        5: (* DWaitPlace: target queue refills continuously (batch engine) *)
            IF abResDone[iR] THEN
                abResDone[iR] := FALSE;
                stRsp := astResRsp[iR];
                IF stRsp.bOk THEN
                    IF m_abClJob[iR] THEN
                        THIS.StoreItem(iR, DINT_TO_UINT(SINT_TO_DINT(m_iPlaceSlot[iR])), stRsp, FALSE, -1);
                        m_iPlaceSlot[iR] := m_iPlaceSlot[iR] + 1;
                        IF m_iPlaceSlot[iR] > UINT_TO_SINT(m_astJob[iR].uiCount) THEN
                            m_aeDSt[iR] := 6;   (* All slots complete *)
                        ELSE
                            m_aeDSt[iR] := 4;   (* Next slot target *)
                        END_IF
                    ELSE
                        THIS.StoreItem(iR, m_astJob[iR].uiCount, stRsp, FALSE, -1);
                        m_aeDSt[iR] := 2;       (* Next cup *)
                    END_IF
                ELSE
                    (* No target available this cycle: re-arm DReqPlace so a
                       fresh reservation pulse is issued on the next cycle *)
                    m_aeDSt[iR] := 4;
                END_IF
            ELSIF NOT bEnable THEN
                THIS.Abandon(iR);
            END_IF

        6: (* DOffer *)
            ajobOffer[iR] := m_astJob[iR];
            abJobPulse[iR] := TRUE;
            m_aeDSt[iR] := 7;

        7: (* DWaitJob *)
            IF abJobResDone[iR] THEN
                abJobResDone[iR] := FALSE;
                m_aeDSt[iR] := 1;
            ELSIF (NOT bEnable) OR g_astRobStat[iR].bFault THEN
                m_aeDSt[iR] := 1;               (* Main cancels the job *)
            END_IF

        ELSE
            m_aeDSt[iR] := 1;
    END_CASE
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: StoreItem (parent SP_Dispatch) - internal
   Write a reservation result into the job under construction.
   bPick = TRUE: new item slot (product side); FALSE: place side of slot
   uiCnt (target pose and place queue index). iCup assigns the gripper
   cup (-1 = default sequential cup = slot position, legacy path).
   ----------------------------------------------------------------------- *)
METHOD StoreItem : BOOL
VAR_INPUT
    (* Robot whose item is being stored *)
    iR    : SINT;
    (* Job item position being filled *)
    uiCnt : UINT;
    (* Reservation response carrying the pick pose *)
    stRsp : ST_SP_ResRsp;
    (* TRUE = pick side record, FALSE = place side *)
    bPick : BOOL;
    (* Cup id (1..GC_CUPS, -1 = uiCnt legacy mapping) *)
    iCup  : SINT;
END_VAR
VAR
    (* Job item record being completed *)
    stJI : ST_SP_JobItem;
END_VAR
    StoreItem := TRUE;              (* Item record written *)
    stJI := m_astJob[iR].astItems[uiCnt];

    IF bPick THEN
        stJI.stItem := stRsp.stItem;
        stJI.iIdx := stRsp.iIdx;
        stJI.iFeedPick := m_iPickFeed[iR];
        stJI.p3Pick := stRsp.p3Pick;
        stJI.uiTool := m_uiTool[iR];
        IF (iCup >= 1) AND (iCup <= GC_CUPS) THEN
            stJI.uiCup := DINT_TO_UINT(SINT_TO_DINT(iCup));
        ELSE
            stJI.uiCup := uiCnt;    (* Legacy sequential cup mapping *)
        END_IF
        stJI.bPick := TRUE;
        (* Advance tool only if the next tool bit is present in uiToolMask *)
        m_uiTool[iR] := m_uiTool[iR] + UINT#1;
        IF (m_uiTool[iR] > UDINT_TO_UINT(SINT_TO_UDINT(GC_TOOLS)))
           OR ((g_astRobStat[iR].uiToolMask
                AND SHL(UINT#1, UINT_TO_INT(m_uiTool[iR] - UINT#1))) = UINT#0) THEN
            m_uiTool[iR] := UINT#1;
        END_IF
    ELSE
        stJI.p3Place := stRsp.p3Pick;       (* Target pose on the outfeed *)
        stJI.iIdxPlace := stRsp.iIdx;
        stJI.iFeedPlace := m_iPlaceFeed[iR];
        stJI.stTgt := stRsp.stItem;         (* v1.4: target capture data for the native tracked place *)
        stJI.bPlace := TRUE;
    END_IF

    m_astJob[iR].astItems[uiCnt] := stJI;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Abandon (parent SP_Dispatch) - internal
   Release the partial job when the system stops mid-handshake: the
   cancellation (with the partial job) is published; the wiring program
   releases the queue records via feed.Release and confirms.
   ----------------------------------------------------------------------- *)
METHOD Abandon : BOOL
VAR_INPUT
    (* Robot whose item is being stored *)
    iR : SINT;
END_VAR
    Abandon := TRUE;                (* Cancellation published *)
    astCancel[iR].bCancel := TRUE;
    astCancel[iR].stJob := m_astJob[iR];
    abCancelPulse[iR] := TRUE;
    m_astJob[iR].uiCount := UINT#0;
    m_abClReq[iR] := FALSE;
    m_abClJob[iR] := FALSE;
    m_iPlaceSlot[iR] := 0;
    m_aeDSt[iR] := 1;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ResetAll (parent SP_Dispatch)
   Drop every partial job (system reset).
   ----------------------------------------------------------------------- *)
METHOD ResetAll : BOOL
VAR
    (* Robot loop index (global reset) *)
    i : SINT;
END_VAR
    ResetAll := TRUE;               (* Registry cleared *)
    FOR i := 1 TO GC_ROBOTS DO
        m_astJob[i].uiCount := UINT#0;
        m_aeDSt[i] := 1;
        m_abClReq[i] := FALSE;
        m_abClJob[i] := FALSE;
        m_iPlaceSlot[i] := 0;
    END_FOR
END_METHOD
