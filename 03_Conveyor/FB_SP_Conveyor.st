(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 03_Conveyor
   Worksheet : FB - SP_Conveyor
   -----------------------------------------------------------------------------
   Purpose   : Per-conveyor manager: position/speed acquisition, filtering,
               slow & stop region arbitration and drive command.
               Feature parity (MotoPick 4):
                 - Slow down when a product/target approaches a critical
                   region (robot-specific thresholds via cfg).
                 - Stop the conveyor as final measure so no items are lost.
                 - Automatic restart when the region condition clears.
                 - Pause/resume never loses belt position (encoder based).
   -----------------------------------------------------------------------------
   Wiring    : PRG_SP_TaskFast assigns ioAxis and cyclic inputs; SP_System feeds
               rNearDist from the tracking queues (min distance upstream).
   =============================================================================
*)

FUNCTION_BLOCK SP_Conveyor
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable  : BOOL;            (* Master enable (system running) *)
    rNearDist: LREAL;           (* Nearest item distance upstream of pick line [mm]; GC_REAL_MAX when none *)
    rDtSec   : LREAL;           (* Task period [s] *)
    bSim     : BOOL;            (* Simulated conveyor *)
    rSimPos  : LREAL;           (* Simulated belt position [mm] *)
    rSimFrc  : LREAL;           (* Simulated speed factor override (scenario) *)
END_VAR
VAR_IN_OUT
    ioAxis : AXIS_REF;          (* Encoder / belt axis *)
END_VAR
VAR_OUTPUT
    stOut : ST_SP_ConvStat;     (* Published status (HMI + system) *)
END_VAR
VAR
    stCfg   : ST_SP_ConvCfg;    (* Configuration (validated by Configure) *)
    m_bCfgOk: BOOL;             (* Configuration valid *)
    m_rPosPrev : LREAL;         (* Previous cycle position [mm] *)
    m_bPosInit : BOOL := FALSE; (* First position acquired *)
    m_Enc : SP_ConvEncoder;     (* Encoder adapter *)
    m_Drv : SP_ConvDrive;       (* Drive adapter *)
    m_Flt : SP_MovAvg;          (* Speed filter *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF NOT m_bCfgOk THEN
    stOut.bActive := FALSE;
    RETURN;
END_IF

(* 1) Belt position ------------------------------------------------------- *)
m_Enc(
    bEnable := bEnable,
    bSim    := bSim,
    rSimPos := rSimPos,
    rPos    => stOut.rPos,
    bValid  => stOut.bActive,
    ioAxis  := ioAxis
);

(* 2) Belt speed ---------------------------------------------------------- *)
IF stOut.bActive THEN
    IF m_bPosInit AND (rDtSec > 0.0) THEN
        m_Flt(
            rIn     := (stOut.rPos - m_rPosPrev) * stCfg.rEncScale * SINT_TO_LREAL(stCfg.iDir) / rDtSec,
            bEnable := TRUE,
            rOut    => stOut.rSpeed,
            bFilled =>
        );
        IF ABS(stOut.rSpeed) < GC_SPEED_MIN THEN
            stOut.rSpeed := 0.0;    (* Deadband: belt considered stopped *)
        END_IF
    ELSE
        m_Flt(bEnable := FALSE, rIn := 0.0, rOut => stOut.rSpeed, bFilled => );
    END_IF
    m_rPosPrev := stOut.rPos;
    m_bPosInit := TRUE;
ELSE
    m_bPosInit := FALSE;
END_IF

(* 3) Slow & stop arbitration -------------------------------------------- *)
stOut.rReqFactor := THIS.FactorFor(rNearDist);
IF bSim THEN
    stOut.rReqFactor := rSimFrc;    (* Scenario override in simulation *)
END_IF
stOut.bInSlow := (stOut.rReqFactor < 0.999) AND (stOut.rReqFactor > 0.001);
stOut.bInStop := (stOut.rReqFactor <= 0.001);
stOut.bSim    := bSim;

(* 4) Drive command ------------------------------------------------------- *)
m_Drv(
    bEnable   := bEnable AND stCfg.bUsed,
    eMode     := stCfg.eDrive,
    rFactor   := stOut.rReqFactor,
    rMaxSpeed := stCfg.rMaxSpeed,
    rAccel    := stCfg.rAccel,
    uiAnaCh   := stCfg.uiAnaCh,
    rCmdSpeed => ,
    ioAxis    := ioAxis
);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_Conveyor)
   Validate and store the configuration. Returns Done or ErrParam.
   Validation rules: scale > 0, maxSpeed > 0, window inside belt,
   stopAhead <= slowAhead, slowFactor in (0.05..1].
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Configuration record applied inside Configure() *)
    stIn : ST_SP_ConvCfg;
END_VAR
    Configure := ET_SP_RetCode#Done;

    IF stIn.rEncScale <= 0.0 THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF stIn.rMaxSpeed <= 0.0 THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF (stIn.iDir <> 1) AND (stIn.iDir <> -1) THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF stIn.rStopAhead > stIn.rSlowAhead THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF (stIn.rSlowFactor <= 0.05) OR (stIn.rSlowFactor > 1.0) THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSE
        stCfg    := stIn;
        stCfg.rWinStart := FUN_SP_Clamp(stIn.rWinStart, 0.0, GC_REAL_MAX);
        stCfg.rWinLen   := FUN_SP_Clamp(stIn.rWinLen, 1.0, GC_REAL_MAX);
        m_bCfgOk := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: FactorFor (parent SP_Conveyor)
   Pure speed-factor arbitration given the nearest item distance upstream
   of the pick line. Automatic restart is implicit: when the item is
   picked (distance grows / becomes GC_REAL_MAX) factor returns to 1.
   ----------------------------------------------------------------------- *)
METHOD FactorFor : LREAL
VAR_INPUT
    rNearDist : LREAL;      (* Distance upstream of pick line [mm] *)
END_VAR
    IF rNearDist <= stCfg.rStopAhead THEN
        FactorFor := 0.0;               (* Stop: protect the item *)
    ELSIF rNearDist <= stCfg.rSlowAhead THEN
        FactorFor := stCfg.rSlowFactor; (* Slow down *)
    ELSE
        FactorFor := 1.0;               (* Full speed *)
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: InWindow (parent SP_Conveyor)
   TRUE when a belt-relative offset (distance upstream of pick line [mm])
   lies inside the tracking window. Used by purge diagnostics and HMI.
   ----------------------------------------------------------------------- *)
METHOD InWindow : BOOL
VAR_INPUT
    rBeltOff : LREAL;   (* Distance upstream of pick line [mm] *)
END_VAR
    InWindow := (rBeltOff >= 0.0) AND (rBeltOff <= (stCfg.rWinStart + stCfg.rWinLen));
END_METHOD
