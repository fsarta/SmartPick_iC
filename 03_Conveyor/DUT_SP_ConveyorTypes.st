(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 03_Conveyor
   Worksheet : DUT - ST_SP_ConveyorTypes
   -----------------------------------------------------------------------------
   Purpose   : Configuration and status structures for tracked conveyors.
               Belt position and speed are expressed in user units (mm).
               The encoder axis is bound via VAR_IN_OUT on the adapter FBs
               (allowed on FBs; never used inside methods).
   =============================================================================
*)

TYPE ST_SP_ConvCfg :
STRUCT
    bUsed       : BOOL;         (* Feed enabled in the system layout *)
    sName       : STRING(16);   (* Human readable conveyor name *)
    rEncScale   : LREAL;        (* User units per encoder unit [mm/cnt] *)
    iDir        : SINT;         (* Belt direction vs encoder: +1 / -1 *)
    rMaxSpeed   : LREAL;        (* Max belt speed [mm/s] *)
    rWinStart   : LREAL;        (* Distance pick-line -> window start, upstream [mm] *)
    rWinLen     : LREAL;        (* Tracking window length [mm] *)
    rSlowAhead  : LREAL;        (* Slow-down threshold ahead of pick line [mm] *)
    rStopAhead  : LREAL;        (* Stop threshold ahead of pick line [mm] *)
    rSlowFactor : LREAL;        (* Speed factor inside slow region [0.05..1] *)
    eDrive      : ET_SP_ConvDriveMode; (* Drive technology *)
    uiAnaCh     : UINT;         (* Analog channel index (GVL_SP_Io.grConvDrive) *)
    rAccel      : LREAL;        (* Belt acceleration [mm/s2] (servo mode) *)
    bStopIdle   : BOOL;         (* Stop belt when no items are tracked *)
END_STRUCT
END_TYPE

TYPE ST_SP_ConvStat :
STRUCT
    rPos        : LREAL;        (* Belt position [mm, monotonic encoder] *)
    rSpeed      : LREAL;        (* Signed belt speed [mm/s] *)
    bActive     : BOOL;         (* Belt enabled and position valid *)
    bInSlow     : BOOL;         (* Slow region active *)
    bInStop     : BOOL;         (* Stop region active *)
    rReqFactor  : LREAL;        (* Requested speed factor [0..1] *)
    udiTrigCnt  : UDINT;        (* Distance trigger counter (camera support) *)
    bSim        : BOOL;         (* TRUE = simulated conveyor *)
END_STRUCT
END_TYPE
