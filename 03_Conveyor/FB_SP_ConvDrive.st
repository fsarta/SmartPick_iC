(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 03_Conveyor
   Worksheet : FB - SP_ConvDrive
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE ADAPTER - conveyor speed command.
               Three drive technologies (configurable per conveyor):
                 - Analog    : speed factor written to GVL_SP_Io.grConvDrive
                               (integrator maps the array element to a %QW
                               analog output scaling in the hardware sheet).
                 - ServoAxis : MC_MoveVelocity on the belt servo axis.
                 - External  : speed commanded by external PLC; SmartPick
                               only publishes the requested factor.
               Simulated mode: factor published, no firmware involvement.

   FW BINDING (CONFIRM on target):
     - MC_MoveVelocity parameter set follows PLCopen Part 1.
   =============================================================================
*)

FUNCTION_BLOCK SP_ConvDrive
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable   : BOOL;           (* Drive enable *)
    eMode     : ET_SP_ConvDriveMode;
    rFactor   : LREAL;          (* Requested speed factor [0..1] *)
    rMaxSpeed : LREAL;          (* Belt speed at factor = 1 [mm/s] *)
    rAccel    : LREAL;          (* Belt acceleration [mm/s2] *)
    uiAnaCh   : UINT;           (* Analog channel index *)
END_VAR
VAR_OUTPUT
    rCmdSpeed : LREAL;          (* Commanded belt speed [mm/s] *)
END_VAR
VAR_IN_OUT
    ioAxis : AXIS_REF;          (* Belt servo axis (ServoAxis mode) *)
END_VAR
VAR
    (* CONFIRM: PLCopen Part 1 velocity FB instance *)
    m_fbVel   : MC_MoveVelocity;
    m_bExec   : BOOL := FALSE;  (* Execute edge generator *)
    m_bPrev   : BOOL := FALSE;
    m_rLastF  : LREAL := -1.0;  (* Last issued factor *)
    m_iCh     : DINT;           (* Clamped analog channel index *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
rCmdSpeed := rMaxSpeed * FUN_SP_Clamp(rFactor, 0.0, 1.0);
m_iCh := FUN_SP_ClampI(UINT_TO_DINT(uiAnaCh), 1, SINT_TO_DINT(GC_FEEDS));

(* External mode: publish only *)
IF eMode = ET_SP_ConvDriveMode#External THEN
    GVL_SP_Io.grConvDrive[m_iCh] := rFactor;
    rCmdSpeed := rFactor;
    RETURN;
END_IF

(* Analog mode: write scaled factor to the analog output mirror *)
IF eMode = ET_SP_ConvDriveMode#Analog THEN
    GVL_SP_Io.grConvDrive[m_iCh] := FUN_SP_Clamp(rFactor, 0.0, 1.0);
    RETURN;
END_IF

(* ServoAxis mode: MC_MoveVelocity with edge retrigger on factor change *)
m_bExec := FALSE;
IF bEnable THEN
    IF (NOT m_bPrev) OR (ABS(rCmdSpeed - m_rLastF) > 0.5) THEN
        m_bExec  := TRUE;       (* Rising edge or relevant speed change *)
        m_rLastF := rCmdSpeed;
    END_IF
END_IF
m_bPrev := bEnable;

m_fbVel(
    Axis        := ioAxis,
    Execute     := m_bExec,
    Velocity    := rCmdSpeed,
    Acceleration:= rAccel,
    Deceleration:= rAccel,
    InVelocity  => ,
    Busy        => ,
    CommandAborted => ,
    Error       => ,
    ErrorID     =>
);
END_FUNCTION_BLOCK
