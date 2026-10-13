(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 14_Collision
   Worksheet : FB - SP_Collision
   -----------------------------------------------------------------------------
   Purpose   : Advanced inter-robot crash prevention (roadmap R-05b).
               Superset of the base SP_ZoneGuard (kept for compatibility):

     1. Zone exclusion (legacy parity): at most ONE robot holds a zone;
        the grant is LATCHED until the request drops, so a robot is never
        disarmed mid-path.
     2. Ordered multi-zone acquisition: a robot may request up to TWO
        zones per cycle (pick zone + place zone). The body normalizes
        every request pair (clamp / dedupe / ascending sort) and grants
        zones strictly in ascending order: a zone k is only granted to a
        robot that holds no zone with a HIGHER id and has no lower own
        request still pending (resource hierarchy). Circular wait is
        impossible -> deadlock-free by construction.
     3. Priority service: when a zone is free, the eligible waiter with
        the best (lowest) priority rank is served; ties break by robot id.
        Starvation is bounded because holds last one job at most.
     4. Zone speed limits: each zone may cap the velocity scale of its
        holders (transfer / crossing areas).
     5. Dynamic TCP separation: for every pair of robots sharing at least
        one requested/held zone (or ALL pairs with bSepAll), the guard
        slows the lower-priority robot on approach (linear ramp below
        rSlowDist) and freezes it below rStopDist (latched, released with
        a 10 % margin against chatter). The higher-priority robot of the
        pair is never limited by the pair.
     6. Diagnostics: per-zone holder / waiters / grant / contention
        counters and per-robot accumulated wait time (layout KPI).

   Wiring (PRG_SP_TaskFast): requests are built from the status mirrors of the
   previous cycle (zone of the pick feed + zone of the place feed, the FB
   normalizes them); positions come from the same mirrors. Outputs feed
   robX.bZoneOk (grant) and robX.rVelScale (speed scaling). SepStop states
   should raise a cell alarm (Main, alarm id 30 + robot).

   Constraints: no pointers, no references, no FB arrays, no actions,
   no VAR_IN_OUT. Pure logic - callable from any POU.
   =============================================================================
*)

FUNCTION_BLOCK SP_Collision
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable : BOOL;             (* Master gate (FALSE = transparent) *)
    bSysRun : BOOL;             (* FALSE = production stopped: release all *)
    uiDtMs  : UDINT;            (* Task period [ms] (wait-time accounting) *)
    (* Current TCP positions (world frame) *)
    ap2Pos  : ARRAY[1..GC_ROBOTS] OF ST_SP_Pose2D;
    (* Requested zones per robot: aiReq[r][1..2], 0 = none. The FB clamps,
       deduplicates and sorts each pair ascending (defensive). *)
    aiReq   : ARRAY[1..GC_ROBOTS] OF ARRAY[1..2] OF SINT;
END_VAR
VAR_OUTPUT
    (* Per-robot verdict (grant + velocity scale + reason) *)
    astRob : ARRAY[1..GC_ROBOTS] OF ST_SP_RobCol;
    (* Per-zone diagnostics *)
    astZd  : ARRAY[1..GC_ZONES] OF ST_SP_ZoneDiag;
END_VAR
VAR
    (* Public configuration (Main/HMI write, mirrors ST_SP_ColCfg) *)
    stCfg : ST_SP_ColCfg;
    (* Feed -> zone map (0 = unguarded) *)
    m_aiFeedZone : ARRAY[1..GC_FEEDS] OF SINT;
    (* Latched zone holds per robot (ascending, max 2) *)
    m_aiHold : ARRAY[1..GC_ROBOTS] OF ARRAY[1..2] OF SINT;
    (* Latched separation freezes (released with margin) *)
    m_abSepStop : ARRAY[1..GC_ROBOTS] OF BOOL;
    (* TRUE after a valid Configure() *)
    m_bCfgOk : BOOL;
    (* ------------------------- Body working data ----------------------- *)
    (* Robot / zone / slot / pair loop indices *)
    i, j, k, s : SINT;
    (* Normalized request pair per robot (ascending, deduplicated) *)
    aiZ1, aiZ2 : ARRAY[1..GC_ROBOTS] OF SINT;
    (* Zone occupancy counters and holders (rebuilt every cycle) *)
    aiCnt    : ARRAY[1..GC_ZONES] OF SINT;
    (* Grant / scale / reason working vectors *)
    abGrant  : ARRAY[1..GC_ROBOTS] OF BOOL;
arScale  : ARRAY[1..GC_ROBOTS] OF LREAL; (* Per-robot velocity scale output (0.1..1.0, 1.0 = free) *)
aeWhy    : ARRAY[1..GC_ROBOTS] OF ET_SP_ColAct; (* Per-robot current action reason (diagnostic mirror) *)
    (* TRUE while the robot waits for a zone held by someone else *)
    bWaiting : BOOL;
    (* Best waiter scan (zone-centric service) *)
    iBest    : SINT;
iBestPri : SINT;                       (* Highest priority rank among contending robots *)
    (* Hierarchy check result and hold insert position *)
    bOk      : BOOL;
    (* Pair separation helpers *)
    iPriI, iPriJ, iYield : SINT;
rD, rDX, rDY : LREAL;                  (* TCP-TCP separation: distance and planar deltas [mm] *)
    (* TRUE when robot i already holds zone z *)
    bLatched : BOOL;
END_VAR

(* 0) Transparent pass-through ------------------------------------------- *)
IF (NOT bEnable) OR (NOT m_bCfgOk) THEN
    FOR i := 1 TO GC_ROBOTS DO
        m_abSepStop[i] := FALSE;
        m_aiHold[i][1] := GC_ZONE_NONE;
        m_aiHold[i][2] := GC_ZONE_NONE;
        astRob[i].bGrant := TRUE;
        astRob[i].rVelScale := 1.0;
        astRob[i].eWhy := ET_SP_ColAct#None;
    END_FOR
    FOR k := 1 TO GC_ZONES DO
        astZd[k].bHeld := FALSE;
        astZd[k].iHolder := 0;
        astZd[k].uiWaiters := UINT#0;
    END_FOR
    RETURN;
END_IF

(* 1) Production stopped: drop every hold (homing must stay possible) ---- *)
IF NOT bSysRun THEN
    FOR i := 1 TO GC_ROBOTS DO
        m_abSepStop[i] := FALSE;
        m_aiHold[i][1] := GC_ZONE_NONE;
        m_aiHold[i][2] := GC_ZONE_NONE;
        astRob[i].bGrant := TRUE;
        astRob[i].rVelScale := 1.0;
        astRob[i].eWhy := ET_SP_ColAct#None;
    END_FOR
    FOR k := 1 TO GC_ZONES DO
        astZd[k].bHeld := FALSE;
        astZd[k].iHolder := 0;
        astZd[k].uiWaiters := UINT#0;
    END_FOR
    RETURN;
END_IF

(* 2) Defensive request normalization: clamp, dedupe, sort ascending ----- *)
FOR i := 1 TO GC_ROBOTS DO
    aiZ1[i] := aiReq[i][1];
    aiZ2[i] := aiReq[i][2];
    IF (aiZ1[i] < 1) OR (aiZ1[i] > GC_ZONES) THEN aiZ1[i] := GC_ZONE_NONE; END_IF
    IF (aiZ2[i] < 1) OR (aiZ2[i] > GC_ZONES) THEN aiZ2[i] := GC_ZONE_NONE; END_IF
    IF (aiZ2[i] <> GC_ZONE_NONE) AND (aiZ1[i] = GC_ZONE_NONE) THEN
        aiZ1[i] := aiZ2[i];         (* Compact: keep the pair contiguous *)
        aiZ2[i] := GC_ZONE_NONE;
    END_IF
    IF (aiZ1[i] <> GC_ZONE_NONE) AND (aiZ1[i] = aiZ2[i]) THEN
        aiZ2[i] := GC_ZONE_NONE;    (* Duplicate request *)
    END_IF
    IF (aiZ1[i] <> GC_ZONE_NONE) AND (aiZ2[i] <> GC_ZONE_NONE) AND (aiZ2[i] < aiZ1[i]) THEN
        j := aiZ1[i];  aiZ1[i] := aiZ2[i];  aiZ2[i] := j;   (* Ascending *)
    END_IF
END_FOR

(* 3) Release latched holds that the request no longer contains ---------- *)
FOR i := 1 TO GC_ROBOTS DO
    FOR s := 1 TO 2 DO
        IF m_aiHold[i][s] <> GC_ZONE_NONE THEN
            IF (m_aiHold[i][s] <> aiZ1[i]) AND (m_aiHold[i][s] <> aiZ2[i]) THEN
                m_aiHold[i][s] := GC_ZONE_NONE;
            END_IF
        END_IF
    END_FOR
    IF (m_aiHold[i][1] = GC_ZONE_NONE) AND (m_aiHold[i][2] <> GC_ZONE_NONE) THEN
        m_aiHold[i][1] := m_aiHold[i][2];   (* Keep the pair contiguous *)
        m_aiHold[i][2] := GC_ZONE_NONE;
    END_IF
END_FOR

(* 4) Rebuild occupancy and reset the working vectors --------------------- *)
FOR k := 1 TO GC_ZONES DO
    aiCnt[k] := 0;
    astZd[k].bHeld := FALSE;
    astZd[k].iHolder := 0;
    astZd[k].uiWaiters := UINT#0;
END_FOR
FOR i := 1 TO GC_ROBOTS DO
    FOR s := 1 TO 2 DO
        IF m_aiHold[i][s] <> GC_ZONE_NONE THEN
            aiCnt[m_aiHold[i][s]] := aiCnt[m_aiHold[i][s]] + 1;
            astZd[m_aiHold[i][s]].bHeld := TRUE;
            IF astZd[m_aiHold[i][s]].iHolder = 0 THEN
                astZd[m_aiHold[i][s]].iHolder := i;
            END_IF
        END_IF
    END_FOR
    abGrant[i] := TRUE;
    aeWhy[i] := ET_SP_ColAct#None;
    arScale[i] := 1.0;
END_FOR

(* 5) Serve free zones to the best eligible waiter (zone-centric, ascending
       so the hierarchy sees the holds latched earlier in this same pass) -- *)
FOR k := 1 TO GC_ZONES DO
    IF aiCnt[k] = 0 THEN
        iBest := 0;
        iBestPri := 32000;
        FOR i := 1 TO GC_ROBOTS DO
            IF (aiZ1[i] = k) OR (aiZ2[i] = k) THEN
                (* Not already latched on this robot *)
                bLatched := (m_aiHold[i][1] = k) OR (m_aiHold[i][2] = k);
                IF NOT bLatched THEN
                    (* Hierarchy: no hold with a higher id may exist *)
                    bOk := TRUE;
                    FOR s := 1 TO 2 DO
                        IF (m_aiHold[i][s] <> GC_ZONE_NONE)
                           AND (m_aiHold[i][s] > k) THEN
                            bOk := FALSE;   (* Would break the global order *)
                        END_IF
                    END_FOR
                    (* Own-pair ordering: lower request must be held first *)
                    IF bOk AND (aiZ1[i] <> GC_ZONE_NONE) AND (aiZ1[i] < k) THEN
                        bLatched := (m_aiHold[i][1] = aiZ1[i])
                                    OR (m_aiHold[i][2] = aiZ1[i]);
                        IF NOT bLatched THEN
                            bOk := FALSE;
                        END_IF
                    END_IF
                    IF bOk THEN
                        iPriI := stCfg.aiPriority[i];
                        IF (iBest = 0) OR (iPriI < iBestPri)
                           OR ((iPriI = iBestPri) AND (i < iBest)) THEN
                            iBest := i;
                            iBestPri := iPriI;
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_FOR
        IF iBest > 0 THEN
            (* Latch the zone into the winner's hold pair (ascending insert) *)
            IF m_aiHold[iBest][1] = GC_ZONE_NONE THEN
                m_aiHold[iBest][1] := k;
            ELSIF m_aiHold[iBest][2] = GC_ZONE_NONE THEN
                IF k < m_aiHold[iBest][1] THEN
                    m_aiHold[iBest][2] := m_aiHold[iBest][1];
                    m_aiHold[iBest][1] := k;
                ELSE
                    m_aiHold[iBest][2] := k;
                END_IF
            END_IF
            aiCnt[k] := 1;
            astZd[k].bHeld := TRUE;
            astZd[k].iHolder := iBest;
            astZd[k].udiGrant := astZd[k].udiGrant + UDINT#1;
        END_IF
    END_IF
END_FOR

(* 6) Waiting robots: request pending on a zone held by somebody else ----- *)
FOR i := 1 TO GC_ROBOTS DO
    bWaiting := FALSE;
    IF (aiZ1[i] <> GC_ZONE_NONE) THEN
        bLatched := (m_aiHold[i][1] = aiZ1[i]) OR (m_aiHold[i][2] = aiZ1[i]);
        IF NOT bLatched THEN
            bWaiting := TRUE;
            astZd[aiZ1[i]].uiWaiters := astZd[aiZ1[i]].uiWaiters + UINT#1;
            astZd[aiZ1[i]].udiCont := astZd[aiZ1[i]].udiCont + UDINT#1;
        END_IF
    END_IF
    IF (aiZ2[i] <> GC_ZONE_NONE) THEN
        bLatched := (m_aiHold[i][1] = aiZ2[i]) OR (m_aiHold[i][2] = aiZ2[i]);
        IF NOT bLatched THEN
            bWaiting := TRUE;
            astZd[aiZ2[i]].uiWaiters := astZd[aiZ2[i]].uiWaiters + UINT#1;
            astZd[aiZ2[i]].udiCont := astZd[aiZ2[i]].udiCont + UDINT#1;
        END_IF
    END_IF
    IF bWaiting THEN
        abGrant[i] := FALSE;
        aeWhy[i] := ET_SP_ColAct#WaitZone;
    END_IF
END_FOR

(* 7) Zone speed limits (holder side) ------------------------------------- *)
FOR i := 1 TO GC_ROBOTS DO
    FOR s := 1 TO 2 DO
        IF m_aiHold[i][s] <> GC_ZONE_NONE THEN
            IF arScale[i] > THIS.ZoneLimOf(m_aiHold[i][s]) THEN
                arScale[i] := THIS.ZoneLimOf(m_aiHold[i][s]);
                IF aeWhy[i] = ET_SP_ColAct#None THEN
                    aeWhy[i] := ET_SP_ColAct#SlowZone;
                END_IF
            END_IF
        END_IF
    END_FOR
END_FOR

(* 8) Dynamic TCP separation ---------------------------------------------- *)
IF stCfg.bDynaSep THEN
    FOR i := 1 TO GC_ROBOTS DO
        FOR j := (i + 1) TO GC_ROBOTS DO
            IF stCfg.bSepAll OR THIS.PairSharesZone(i, j) THEN
                rDX := ap2Pos[i].rX - ap2Pos[j].rX;
                rDY := ap2Pos[i].rY - ap2Pos[j].rY;
                rD  := SQRT(rDX * rDX + rDY * rDY);
                (* Lower priority yields: larger rank value = lower priority *)
                iPriI := stCfg.aiPriority[i];
                iPriJ := stCfg.aiPriority[j];
                IF iPriI > iPriJ THEN
                    iYield := i;
                ELSIF iPriJ > iPriI THEN
                    iYield := j;
                ELSIF i < j THEN
                    iYield := j;        (* Tie: the higher id yields *)
                ELSE
                    iYield := i;
                END_IF
                IF rD < stCfg.rStopDist THEN
                    m_abSepStop[iYield] := TRUE;    (* Latched freeze *)
                ELSIF rD > (stCfg.rStopDist * 1.1) THEN
                    m_abSepStop[iYield] := FALSE;   (* Release with margin *)
                END_IF
                IF m_abSepStop[iYield] THEN
                    abGrant[iYield] := FALSE;
                    aeWhy[iYield] := ET_SP_ColAct#SepStop;
                ELSIF rD < stCfg.rSlowDist THEN
                    (* Linear ramp between the two thresholds *)
                    IF stCfg.rSlowDist > stCfg.rStopDist THEN
                        arScale[iYield] := arScale[iYield]
                            * ((rD - stCfg.rStopDist) / (stCfg.rSlowDist - stCfg.rStopDist));
                    ELSE
                        arScale[iYield] := 0.1;
                    END_IF
                    IF arScale[iYield] < 0.1 THEN
                        arScale[iYield] := 0.1;
                    END_IF
                    IF aeWhy[iYield] = ET_SP_ColAct#None THEN
                        aeWhy[iYield] := ET_SP_ColAct#SepSlow;
                    END_IF
                END_IF
            END_IF
        END_FOR
    END_FOR
END_IF

(* 9) Publish + wait-time accounting --------------------------------------- *)
FOR i := 1 TO GC_ROBOTS DO
    astRob[i].bGrant := abGrant[i];
    astRob[i].rVelScale := arScale[i];
    astRob[i].eWhy := aeWhy[i];
    IF NOT abGrant[i] THEN
        astRob[i].udiWaitMs := astRob[i].udiWaitMs + uiDtMs;
    END_IF
END_FOR
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_Collision)
   Store the feed -> zone map (0 = unguarded), mirroring SP_ZoneGuard.
   Values outside 0..GC_ZONES are clamped to 0 (unguarded, fail-safe).
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Feed -> zone map (0 = unguarded) *)
    aiFeedZone : ARRAY[1..GC_FEEDS] OF SINT;
END_VAR
VAR
    (* Feed loop index (map validation) *)
    i : SINT;
    (* Zone id being validated *)
    iZ : SINT;
END_VAR
    Configure := ET_SP_RetCode#Done;
    FOR i := 1 TO GC_FEEDS DO
        iZ := aiFeedZone[i];
        IF (iZ < 1) OR (iZ > GC_ZONES) THEN
            iZ := GC_ZONE_NONE;
        END_IF
        m_aiFeedZone[i] := iZ;
    END_FOR
    m_bCfgOk := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ZoneLimOf (parent SP_Collision) - internal
   Speed limit of a zone id (1.0 = unlimited / unconfigured).
   ----------------------------------------------------------------------- *)
METHOD ZoneLimOf : LREAL
VAR_INPUT
    (* Zone id (1..GC_ZONES) *)
    iZone : SINT;
END_VAR
    ZoneLimOf := 1.0;
    IF (iZone >= 1) AND (iZone <= GC_ZONES) THEN
        IF stCfg.arZoneLim[iZone] > 0.0 THEN
            ZoneLimOf := stCfg.arZoneLim[iZone];
        END_IF
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: PairSharesZone (parent SP_Collision) - internal
   TRUE when robots i and j currently hold at least one common zone
   (their latched zone sets intersect).
   ----------------------------------------------------------------------- *)
METHOD PairSharesZone : BOOL
VAR_INPUT
    (* First robot id *)
    i : SINT;
    (* Second robot id *)
    j : SINT;
END_VAR
VAR
    (* Hold slot loop indices *)
    k, m : SINT;
END_VAR
    PairSharesZone := FALSE;
    FOR k := 1 TO 2 DO
        FOR m := 1 TO 2 DO
            IF (m_aiHold[i][k] <> GC_ZONE_NONE)
               AND (m_aiHold[i][k] = m_aiHold[j][m]) THEN
                PairSharesZone := TRUE;
                RETURN;
            END_IF
        END_FOR
    END_FOR
END_METHOD
