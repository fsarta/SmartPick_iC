(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FB - SP_DrvGeneric
   -----------------------------------------------------------------------------
   Purpose   : Generic TCP camera driver: pure forwarder to SP_DrvAscii with
               user-defined protocol template (no brand presets). The full
               protocol is defined by the configuration fields:
                 - sSendFmt : send template with optional {SEQ} macro
                 - sDelim   : result token delimiter
                 - uiIdx*   : 1-based token indexes (type,x,y,theta,score)
                 - sEndTok  : end-of-response token ('' = idle based)
   =============================================================================
*)

FUNCTION_BLOCK SP_DrvGeneric
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
    stCfg       : ST_SP_VisionCfg;   (* Public config passthrough *)
END_VAR
VAR
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
   METHOD: Configure (parent SP_DrvGeneric)
   Fill only the safety-neutral defaults, forward to the engine.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* User configuration (all protocol fields required) *)
    stIn : ST_SP_VisionCfg;
END_VAR
VAR
    (* Configuration after driver-tag stamping *)
    stPres : ST_SP_VisionCfg;
    (* Engine Configure() result *)
    eRc    : ET_SP_RetCode;
END_VAR
    stPres := stIn;
    stPres.eDrv := ET_SP_VisionDrv#GenericTCP;

    IF LEN(stPres.sDelim) = 0 THEN
        stPres.sDelim := ',';
    END_IF
    IF stPres.uiMaxItems = 0 THEN
        stPres.uiMaxItems := UDINT_TO_UINT(SINT_TO_UDINT(GC_VIS_MAX));
    END_IF

    stCfg := stPres;
    eRc := m_Eng.Configure(stPres);
    Configure := eRc;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetItem (parent SP_DrvGeneric) - forwarded to engine.
   ----------------------------------------------------------------------- *)
METHOD GetItem : BOOL
    GetItem := m_Eng.GetItem();
    out_stItem := m_Eng.out_stItem;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearItems (parent SP_DrvGeneric) - forwarded to engine.
   ----------------------------------------------------------------------- *)
METHOD ClearItems : UDINT
    ClearItems := m_Eng.ClearItems();   (* Discarded item count (engine) *)
END_METHOD
