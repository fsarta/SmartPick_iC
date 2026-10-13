(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 14_Collision
   Worksheet : DUT - ST_SP_ColTypes
   -----------------------------------------------------------------------------
   Purpose   : Advanced crash prevention data model (roadmap R-05b):

     - ET_SP_ColAct  : reason tag per robot (why it is limited).
     - ST_SP_ColCfg  : guard configuration (distances, priorities, per-zone
                       speed limits, dynamic separation switches).
     - ST_SP_ZoneDiag: per-zone diagnostics (holder, waiters, counters).
     - ST_SP_RobCol  : per-robot verdict (grant, velocity scale, reason,
                       accumulated waiting time).

   Safety philosophy (see FB_SP_Collision header for the full protocol):
     grants are only revoked at job boundaries (freeze semantics), speed
     reduction is the primary protective measure and hard stops are
     reserved for separation violations. Deadlock freedom comes from the
     ordered-acquisition protocol (at most 2 ascending zones per robot).
   =============================================================================
*)

TYPE ET_SP_ColAct :
(
    None    := 0,       (* Robot unrestricted *)
    WaitZone:= 1,       (* Frozen: zone held by another robot *)
    SlowZone:= 2,       (* Slow: zone speed limit below 1.0 *)
    SepSlow := 3,       (* Slow: dynamic separation distance low *)
    SepStop := 4        (* Frozen: separation distance critical *)
);
END_TYPE

TYPE ST_SP_ColCfg :
STRUCT
    (* Master switch (FALSE = guard fully transparent) *)
    bEnable  : BOOL;
    (* Dynamic TCP separation monitoring between robots *)
    bDynaSep : BOOL;
    (* TRUE = monitor ALL pairs, FALSE = only pairs sharing a zone *)
    bSepAll  : BOOL;
    (* Separation thresholds [mm]: below rSlowDist the lower-priority
       robot is slowed (linear ramp), below rStopDist it is frozen. *)
    rSlowDist : LREAL;
    rStopDist : LREAL;
    (* Service priority per robot: 1 = highest. Ties break by robot id. *)
    aiPriority : ARRAY[1..GC_ROBOTS] OF SINT;
    (* Zone speed limits [0.1..1.0], 1.0 = full speed (transfer areas) *)
    arZoneLim : ARRAY[1..GC_ZONES] OF LREAL;
END_STRUCT
END_TYPE

TYPE ST_SP_ZoneDiag :
STRUCT
    bHeld    : BOOL;        (* Zone occupied by at least one robot *)
    iHolder  : SINT;        (* Current holder robot id (0 = free) *)
    uiWaiters: UINT;        (* Robots currently waiting for this zone *)
    udiGrant : UDINT;       (* Total grants handed out (statistics) *)
    udiCont  : UDINT;       (* Contention events (request while held) *)
END_STRUCT
END_TYPE

TYPE ST_SP_RobCol :
STRUCT
    bGrant    : BOOL;       (* TRUE = robot free to move *)
    rVelScale : LREAL;      (* Velocity scale 0.1..1.0 *)
    eWhy      : ET_SP_ColAct; (* Reason of the current limitation *)
    udiWaitMs : UDINT;      (* Accumulated frozen time [ms] (layout KPI) *)
END_STRUCT
END_TYPE
