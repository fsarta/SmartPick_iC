(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FB - SP_DrvKeyence
   -----------------------------------------------------------------------------
   Purpose   : Keyence CV-X / XG camera driver (brand wrapper over
               SP_DrvAscii). Applies Keyence default protocol presets and
               forwards to the generic ASCII engine. Custom flow configurations
               are accommodated via the token index fields in cfg.
   Presets   : trigger 'R', delimiter ',', fields type,x,y,theta,score,
               theta in degrees, idle-based end of response.
   Extension : for model-specific handshakes (user area registers, binary
               mode), extend SP_DrvAscii or add brand logic here.
   =============================================================================
*)

FUNCTION_BLOCK SP_DrvKeyence
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    (* TRUE = driver operational (forwarded to engine) *)
    bEnable  : BOOL;
    (* Image trigger (rising edge, forwarded) *)
    bTrig    : BOOL;
    (* Time source (forwarded) *)
    udiTickMs : UDINT;
    (* Belt position at trigger [mm] (stamped into items) *)
    rBeltPos : LREAL;
END_VAR
VAR_OUTPUT
    (* Engine state passthrough *)
    eState      : ET_SP_VisionState;
    (* Image-processed pulse passthrough *)
    bDone       : BOOL;
    (* Error pulse passthrough *)
    bErr        : BOOL;
    (* Error code passthrough (1=open 2=timeout 3=send 4=parse) *)
    uiErr       : UINT;
    (* Items ready for GetItem passthrough *)
    bItemsAvail : BOOL;
    (* GetItem result passthrough *)
    out_stItem  : ST_SP_VisionItem;
END_VAR
VAR
    stCfg   : ST_SP_VisionCfg;   (* Public config passthrough *)
    m_Eng   : SP_DrvAscii;       (* Protocol engine *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
m_Eng(
    bEnable  := bEnable,
    bTrig    := bTrig,
    udiTickMs := udiTickMs,
    rBeltPos := rBeltPos,
    eState      => eState,
    bDone       => bDone,
    bErr        => bErr,
    uiErr       => uiErr,
    bItemsAvail => bItemsAvail,
    out_stItem  => out_stItem
);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_DrvKeyence)
   Apply Keyence defaults for unset fields, then forward to the engine.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* User configuration (empty fields get presets) *)
    stIn : ST_SP_VisionCfg;
END_VAR
VAR
    (* Configuration after applying Keyence defaults *)
    stPres : ST_SP_VisionCfg;
    (* Engine Configure() result *)
    eRc    : ET_SP_RetCode;
END_VAR
    stPres := stIn;
    stPres.eDrv := ET_SP_VisionDrv#Keyence;

    IF LEN(stPres.sTrigStr) = 0 THEN
        stPres.sTrigStr := 'R';
    END_IF
    IF LEN(stPres.sDelim) = 0 THEN
        stPres.sDelim := ',';
    END_IF
    IF stPres.uiIdxType = 0 THEN stPres.uiIdxType  := UINT#1; END_IF
    IF stPres.uiIdxX    = 0 THEN stPres.uiIdxX     := UINT#2; END_IF
    IF stPres.uiIdxY    = 0 THEN stPres.uiIdxY     := UINT#3; END_IF
    IF stPres.uiIdxTh   = 0 THEN stPres.uiIdxTh    := UINT#4; END_IF
    IF stPres.uiIdxScore= 0 THEN stPres.uiIdxScore := UINT#5; END_IF
    IF stPres.uiMaxItems = 0 THEN
        stPres.uiMaxItems := UDINT_TO_UINT(SINT_TO_UDINT(GC_VIS_MAX));
    END_IF

    stCfg := stPres;
    eRc := m_Eng.Configure(stPres);
    Configure := eRc;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetItem (parent SP_DrvKeyence) - forwarded to engine.
   ----------------------------------------------------------------------- *)
METHOD GetItem : BOOL
    GetItem := m_Eng.GetItem();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearItems (parent SP_DrvKeyence) - forwarded to engine.
   ----------------------------------------------------------------------- *)
METHOD ClearItems : UDINT
    ClearItems := m_Eng.ClearItems();   (* Discarded item count (engine) *)
END_METHOD
