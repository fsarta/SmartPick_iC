(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Fw
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE BINDING HUB (closes open points FW-1 / FW-2).

               Every runtime value that depends on the installed iCube
               motion library version is concentrated HERE, so the on-site
               integration is a wiring task in PRG_SP_TaskFast plus at most one
               variable - never a library edit.

   FW-2 (group Ready / referenced status):
     - g_eFwStatMode = 0 (default): proxy mode. SP_RobMotion reports
       bEnabled := bEnable and bHomed := bEnabled (works out of the box,
       required for simulation and acceptable for first power-up tests).
     - g_eFwStatMode = 1: status injection mode. PRG_SP_TaskFast copies the
       real group status bits into g_abFwGrpReady / g_abFwGrpRef below.
       Sources (pick what the installed library exposes, see
       Firmware/FW_PATCH_ConveyorTracking_IT-EN.md):
         a) GroupEnable Done output
         b) a GroupReadStatus / GroupInfo FB output structure
         c) status bits of the AXES_GROUP_REF hardware object
     - Mode and arrays are plain variables (not constants) so the mode can
       be switched from the HMI/init without touching any POU.

   FW-1 (conveyor tracking): CLOSED IN CODE since v1.3.
     FB_SP_RobMotion integrates the Yaskawa MC_TrackConveyorBelt (PLCopen
     Part 4 tracking, confirmed by iCube release notes 2025-6 / 2026-6).
     The run-time selector below switches between the native tracked mode
     and the v1.x cut-off fallback, so the same build runs in simulation,
     on a target without the tracking option, and on a fully equipped one.
     Remaining on-site CONFIRM points (enum/struct spellings only) are
     listed in Firmware/FW_PATCH_ConveyorTracking_IT-EN.md.

   Constraints: no pointers, no references, no FB arrays, no actions.
   =============================================================================
*)

VAR
    (* ------------------- FW-2: group status mode ------------------------ *)
    g_eFwStatMode : SINT := 0;  (* 0 = proxy via enable, 1 = inject real status *)

    (* ------------------- FW-2: injected group status -------------------- *)
    (* PRG_SP_TaskFast wires these from the group status source of the
       installed library. Ignored while g_eFwStatMode = 0. *)
    g_abFwGrpReady : ARRAY[1..GC_ROBOTS] OF BOOL; (* Group enabled / ready   *)
    g_abFwGrpRef   : ARRAY[1..GC_ROBOTS] OF BOOL; (* Group referenced / homed *)

    (* ------------------- FW-1: conveyor tracking mode ------------------- *)
    (* 0 = fallback: cut-off predicted world pose + MCS linear move (v1.x
           behavior, works without the tracking option and in simulation).
       1 = native: MC_TrackConveyorBelt session + PCS synchronized moves
           (full-speed flying pick, firmware-managed belt following).
       Plain variable (not constant) so the mode can be switched from the
       HMI/init or per-line recipe without touching any POU. *)
    g_eTrkMode : SINT := 0;

    (* ------------------- FW-1 v1.4: tracked place selector -------------- *)
    (* Per-feed enable of the NATIVE tracked place (place on the moving
       outfeed through its own MC_TrackConveyorBelt session). A place on
       feed i runs tracked only when ALL of the following hold:
         g_eTrkMode = 1  AND  g_abPlaceTrack[i] = TRUE  AND  the feed belt
         frame is wired (SetBeltFrames). Any other combination places with
       the static cut-off prediction (v1.x behavior). Default FALSE =
       v1.3 behavior, zero change unless enabled. Plain variables so the
       mode can be switched from the HMI/init or per recipe. *)
    g_abPlaceTrack : ARRAY[1..GC_FEEDS] OF BOOL;
END_VAR
