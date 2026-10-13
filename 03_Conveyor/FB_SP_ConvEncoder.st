(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 03_Conveyor
   Worksheet : FB - SP_ConvEncoder
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE ADAPTER - conveyor encoder position acquisition.
               This is one of the very few places where firmware calls live.
               All firmware binding is concentrated here so the core library
               stays portable (adapter pattern).

   FW BINDING (CONFIRM on target iC 9226M-EC, iCube Engineer):
     - Hardware mode: MC_ReadActualPosition on the encoder/belt axis.
       The conveyor encoder must be configured in the iCube hardware
       catalog as encoder axis (or the belt itself as servo axis).
     - Simulated mode: bypasses firmware completely (offline tests).

   Constraints: VAR_IN_OUT ioAxis is assigned at every call site (PRG_SP_TaskFast).
               No method uses VAR_IN_OUT. No pointers, no actions.
   =============================================================================
*)

FUNCTION_BLOCK SP_ConvEncoder
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable : BOOL;             (* TRUE = acquire position this cycle *)
    bSim    : BOOL;             (* TRUE = simulated position source *)
    rSimPos : LREAL;            (* Simulated belt position [mm] *)
END_VAR
VAR_OUTPUT
    rPos    : LREAL;            (* Belt position [encoder units -> scaled] *)
    bValid  : BOOL;             (* Position valid this cycle *)
END_VAR
VAR_IN_OUT
    ioAxis  : AXIS_REF;         (* Encoder / belt axis (firmware binding) *)
END_VAR
VAR
    (* CONFIRM: PLCopen Part 1 read FB instance, standard on iCube Engineer *)
    m_fbRead : MC_ReadActualPosition;
    (* TRUE once the firmware adapter reported a fresh position *)
    m_bValid : BOOL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF bSim THEN
    (* Simulation path: position provided by the simulation framework *)
    rPos   := rSimPos;
    bValid := bEnable;
    RETURN;
END_IF

(* Hardware path: cyclic read of the encoder axis actual position *)
m_fbRead(
    Axis    := ioAxis,
    Enable  := bEnable,
    Valid   => m_bValid,
    Busy    => ,
    Error   => ,
    ErrorID => ,
    Position=> rPos
);
bValid := bEnable AND m_bValid;
END_FUNCTION_BLOCK
