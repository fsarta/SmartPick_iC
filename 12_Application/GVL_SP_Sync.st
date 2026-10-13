(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Sync
   -----------------------------------------------------------------------------
   Purpose   : Inter-task synchronization mailboxes for the 3-task build
               (PRG_SP_TaskFast / PRG_SP_TaskMain / PRG_SP_TaskSvc).

   Concurrency contract (no semaphores exist in plain ST - the whole
   interface is built on single-writer flags and value arrays):

     - bCfgPend    : TaskMain sets, TaskFast clears (config re-apply pulse)
     - stPattCmd   : TaskMain writes the batch request + sets bStart/bAbort,
                     TaskFast executes it on the pattern engine and clears
     - stPattStat  : TaskFast publishes the pattern engine status,
                     TaskMain reads it for batch progress sync
     - astStatEv   : production statistics event ring. udiStatWr is written
                     only by TaskFast, udiStatRd only by TaskMain (UDINT
                     counters, wrap-safe modular difference). When the ring
                     is full the fast task drops the event and counts it in
                     udiStatDrop (HMI diagnostics).
     - stTotPub    : TaskMain publishes the production counters snapshot,
                     TaskSvc reads it for the HMI mirror (HMI-grade data,
                     cosmetic tear is acceptable - never used for control)
     - bLogPend    : TaskMain requests a log line, TaskSvc writes it into
                     the ring logger and clears the flag

   The build is task-agnostic: assigning all three programs to ONE cyclic
   task keeps the same semantics (mailboxes simply add one scan of latency).
   =============================================================================
*)

VAR
    (* ---- Configuration re-apply (TaskMain -> TaskFast) ---------------- *)
    bCfgPend : BOOL;            (* TRUE = pending FB re-configure cycle *)

    (* ---- Pattern batch commands (TaskMain -> TaskFast) ---------------- *)
    stPattCmd : ARRAY[1..2] OF ST_SP_PattCmd;   (* One per outfeed engine *)

    (* ---- Pattern status publication (TaskFast -> TaskMain) ------------ *)
    stPattStat : ARRAY[1..2] OF ST_SP_BatchStat; (* Copy of pattN.stStat  *)

    (* ---- Statistics event ring (TaskFast -> TaskMain) ----------------- *)
    astStatEv  : ARRAY[1..64] OF ST_SP_StatEv;  (* Ring of pick/place/cyc *)
    udiStatWr  : UDINT := UDINT#0;  (* Producer cursor (TaskFast) *)
    udiStatRd  : UDINT := UDINT#0;  (* Consumer cursor (TaskMain) *)
    udiStatDrop: UDINT := UDINT#0;  (* Events dropped when ring full *)

    (* ---- Production counters snapshot (TaskMain -> TaskSvc) ----------- *)
    stTotPub : ST_SP_Counters;  (* Copy of g_Sys.Stats.stTot *)
    rPphPub  : LREAL;           (* Copy of g_Sys.Stats.rPiecesPerH *)

    (* ---- Per-task periods (CONFIRM with the iCube task configuration) - *)
    uiMainDtMs : UDINT := UDINT#10;  (* Period of the application task *)
    uiSvcDtMs  : UDINT := UDINT#100; (* Period of the service task *)

    (* ---- Log request (TaskMain -> TaskSvc) ---------------------------- *)
    bLogPend : BOOL;            (* TRUE = pending log line below *)
    sLogMsg  : STRING(80);      (* Message text (Info level, System src) *)
END_VAR
