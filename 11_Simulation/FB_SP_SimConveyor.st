(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 11_Simulation
   Worksheet : FB - SP_SimConveyor
   -----------------------------------------------------------------------------
   Purpose   : Virtual conveyor encoder for offline tests: integrates the
               commanded speed (set speed x slow/stop factor) into a
               monotonic belt position. Feeds SP_Conveyor in simulation
               mode (bSim = TRUE, rSimPos = output).
   =============================================================================
*)

FUNCTION_BLOCK SP_SimConveyor
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bRun    : BOOL;             (* Belt running *)
    rSetSpd : LREAL;            (* Set speed [mm/s] *)
    rFactor : LREAL;            (* Slow/stop factor [0..1] *)
    uiDtMs  : UDINT;            (* Task period [ms] *)
    bReset  : BOOL;             (* Position reset (start of test) *)
END_VAR
VAR_OUTPUT
    rPos    : LREAL;            (* Virtual belt position [mm] *)
    rSpeed  : LREAL;            (* Virtual belt speed [mm/s] *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF bReset THEN
    rPos := 0.0;
    rSpeed := 0.0;
    RETURN;
END_IF

rSpeed := 0.0;
IF bRun THEN
    rSpeed := rSetSpd * FUN_SP_Clamp(rFactor, 0.0, 1.0);
    rPos := rPos + rSpeed * (UDINT_TO_LREAL(uiDtMs) / 1000.0);
END_IF
END_FUNCTION_BLOCK
