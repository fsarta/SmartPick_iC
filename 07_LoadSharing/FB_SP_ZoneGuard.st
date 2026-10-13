(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 07_LoadSharing
   Worksheet : FB - SP_ZoneGuard
   -----------------------------------------------------------------------------
   Purpose   : Roadmap R-05 (base): inter-robot shared-zone interlock.
               Robots whose work areas overlap (e.g. two robots picking
               from adjacent feeds, or a robot crossing another robot's
               envelope) are granted exclusive access to one zone at a
               time, preventing tool-to-tool collision in shared volumes.

   Model:
     - Each feed is statically assigned to a zone id (1..GC_ZONES) or left
       unguarded (0) via Configure(aiFeedZone).
     - A robot REQUESTS its current feed's zone while it has an active job
       (wired by PRG_SP_TaskFast from the robot status mirrors, one-cycle
       latency at task rate is acceptable).
     - Grant rule: at most ONE robot may HOLD a zone. A granted zone is
       LATCHED until the holder drops the request (job finished / paused /
       idle), so a robot is never disarmed mid-path.
     - Contention is broken by static priority (robot 1 first). Starvation
       is bounded in practice because requests only last for one job.
     - A robot NOT requesting is always granted (idle robots keep moving,
       homing and parking are never blocked).

   Deadlock safety: every robot requests at most ONE zone per cycle
   (the zone of its current feed), therefore no circular wait can form.
   Keep it that way when extending this module.

   Limits (documented, roadmap R-05b): time-sliced sharing for two robots
   that must permanently share one zone, and trajectory-level anti-collision
   (TCP separation checks) are NOT part of this base module. Note: a robot
   whose current feed (hence zone) changes mid-job transfers its hold to
   the new zone atomically in the same cycle; a short overlap with a robot
   entering the just-freed zone is possible while the holder is still
   travelling out - size the zone map so that physically shared volumes
   map to the SAME zone, not to adjacent ones.

   Wiring: no VAR_IN_OUT, no firmware calls - the FB is pure logic and
   may be called from any POU. PRG_SP_TaskFast gates it with
   g_stSysCfg.bZoneGuard and feeds robX.bZoneOk with abGrant[x].

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_ZoneGuard
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable   : BOOL;                           (* FALSE = all grants TRUE *)
    abRobReq  : ARRAY[1..GC_ROBOTS] OF BOOL;    (* Robot requests its feed zone *)
    aiRobFeed : ARRAY[1..GC_ROBOTS] OF SINT;    (* Feed each robot works on *)
END_VAR
VAR_OUTPUT
    abGrant : ARRAY[1..GC_ROBOTS] OF BOOL;      (* TRUE = robot free to move *)
    abHold  : ARRAY[1..GC_ROBOTS] OF BOOL;      (* Latched grant (diagnostic) *)
    auiCnt  : ARRAY[1..GC_ZONES] OF UINT;       (* Current holders per zone *)
    uiWait  : UINT;                             (* Robots waiting for a zone *)
END_VAR
VAR
    m_aiFeedZone : ARRAY[1..GC_FEEDS] OF SINT;  (* Feed -> zone (0 = unguarded) *)
    m_abHold     : ARRAY[1..GC_ROBOTS] OF BOOL; (* Latch state *)
    m_aiRobZone  : ARRAY[1..GC_ROBOTS] OF SINT; (* Resolved zone per robot *)
    m_bInit      : BOOL := FALSE;
    (* Body working variables *)
    i, k, iZ : SINT;
    (* TRUE when no other robot holds the requested zone *)
    bFree : BOOL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)

(* 0) Disabled: transparent pass-through ---------------------------------- *)
IF NOT bEnable THEN
    FOR i := 1 TO GC_ROBOTS DO
        m_abHold[i] := FALSE;
        abHold[i]   := FALSE;
        abGrant[i]  := TRUE;
    END_FOR
    FOR k := 1 TO GC_ZONES DO
        auiCnt[k] := UINT#0;
    END_FOR
    uiWait := UINT#0;
    RETURN;
END_IF

(* 1) Resolve the requested zone of every robot ---------------------------- *)
FOR i := 1 TO GC_ROBOTS DO
    m_aiRobZone[i] := GC_ZONE_NONE;
    IF abRobReq[i] AND (aiRobFeed[i] >= 1) AND (aiRobFeed[i] <= GC_FEEDS) THEN
        iZ := m_aiFeedZone[aiRobFeed[i]];
        IF (iZ >= 1) AND (iZ <= GC_ZONES) THEN
            m_aiRobZone[i] := iZ;
        END_IF
    END_IF
END_FOR

(* 2) Release latched holds whose request dropped --------------------------- *)
(* The hold is kept while the robot keeps requesting the same zone; it is
   released as soon as the request disappears (job done, paused or idle). *)
FOR i := 1 TO GC_ROBOTS DO
    IF m_abHold[i] AND (m_aiRobZone[i] = GC_ZONE_NONE) THEN
        m_abHold[i] := FALSE;
    END_IF
END_FOR

(* 3) Count current holders per zone --------------------------------------- *)
FOR k := 1 TO GC_ZONES DO
    auiCnt[k] := UINT#0;
END_FOR
FOR i := 1 TO GC_ROBOTS DO
    IF m_abHold[i] THEN
        k := m_aiRobZone[i];
        auiCnt[k] := auiCnt[k] + UINT#1;
    END_IF
END_FOR

(* 4) Grant new requests in static priority order --------------------------- *)
uiWait := UINT#0;
FOR i := 1 TO GC_ROBOTS DO
    IF (NOT m_abHold[i]) AND (m_aiRobZone[i] <> GC_ZONE_NONE) THEN
        k  := m_aiRobZone[i];
        bFree := (auiCnt[k] = UINT#0);
        IF bFree THEN
            m_abHold[i] := TRUE;        (* Latch: held until request drops *)
            auiCnt[k] := auiCnt[k] + UINT#1;
        ELSE
            uiWait := uiWait + UINT#1;  (* Waiting for the zone holder *)
        END_IF
    END_IF
END_FOR

(* 5) Publish --------------------------------------------------------------- *)
FOR i := 1 TO GC_ROBOTS DO
    abHold[i]  := m_abHold[i];
    abGrant[i] := (NOT abRobReq[i]) OR m_abHold[i]
                  OR (m_aiRobZone[i] = GC_ZONE_NONE);
END_FOR
m_bInit := TRUE;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_ZoneGuard)
   Store the feed -> zone map. Zone 0 (GC_ZONE_NONE) = feed unguarded.
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
END_METHOD
