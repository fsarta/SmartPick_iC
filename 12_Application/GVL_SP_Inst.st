(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 12_Application
   Worksheet : GVL - GVL_SP_Inst
   -----------------------------------------------------------------------------
   Purpose   : Task-shared FB instances. In the multi-task build (v1.6+) the
               application is split into three programs assigned to three
               cyclic tasks (see 00_TaskConfig_IT-EN.md):

                 PRG_SP_TaskFast (motion task, ~2 ms)  : motion-critical loop
                 PRG_SP_TaskMain (application, ~10 ms) : orchestration loop
                 PRG_SP_TaskSvc  (service, ~100 ms)    : logging, OEE, files

               A FB instance that is TOUCHED by more than one task must be
               declared here (GVL), because programs cannot access each
               other's local variables. Every instance below has exactly one
               OWNER task that calls its body / cyclic methods:

                 g_Sys  : owner PRG_SP_TaskMain (Run); TaskFast and TaskSvc
                          only READ status fields (abConvEnable, abRobPause,
                          stOut ...) - plain data, single writer.
                 g_Disp : owner PRG_SP_TaskMain (Run + Bal.Configure);
                          PRG_SP_TaskFast executes the request side effects
                          (feed.Reserve / rob.OfferJob / release) and fills
                          the response fields (astResRsp, astClRsp,
                          abResDone, astJobRes, abJobResDone) - latched
                          request protocol, see FB_SP_Dispatch header.

               All other instances (conveyors, feeds, robots, cameras,
               pattern engines, guards, service FBs) are single-task and
               stay as local variables of their owning program.
   =============================================================================
*)

VAR
    (* System orchestrator: staged startup, resiliency, batch registry *)
    g_Sys    : SP_System;
    (* Dispatcher: load balancer + reservation/job handshake mailbox *)
    g_Disp   : SP_Dispatch;
END_VAR
