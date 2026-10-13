(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FB - SP_DrvAscii
   -----------------------------------------------------------------------------
   Purpose   : Generic ASCII-over-TCP camera protocol engine (camera driver
               model core). Brand drivers (Cognex, Keyence) are thin
               wrappers around this engine applying default presets; the
               GenericTCP driver uses it directly with user templates.

   Protocol model:
     - Trigger  : configurable ASCII command (cfg.sTrigStr, or cfg.sSendFmt
                  template containing the {SEQ} macro for a sequence number)
     - Response : one line per item, token separated (cfg.sDelim):
                  <type>,<x>,<y>,<theta>,<score>
                  Field order is configurable (cfg.uiIdx*); theta is
                  expected in DEGREES (application convention); cameras
                  reporting radians set cfg.bThInRad and are converted.
     - End of response: cfg.sEndTok token, or idle gap (GC_VIS_IDLE), or
                  overall timeout (cfg.tTimeout).
   -----------------------------------------------------------------------------
   All firmware communication is delegated to SP_Socket (ADR confined).
   Items are exposed one at a time through GetItem (no VAR_IN_OUT used).
   =============================================================================
*)

FUNCTION_BLOCK SP_DrvAscii
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bEnable  : BOOL;            (* TRUE = driver operational *)
    bTrig    : BOOL;            (* Rising edge = image trigger *)
    udiTickMs: UDINT;           (* Monotonic ms tick (GVL_SP_Rtc, v1.8.0) *)
    rBeltPos : LREAL;           (* Belt position at trigger [mm] (stamping) *)
END_VAR
VAR_OUTPUT
    (* Driver lifecycle state (Offline/Connecting/Online/Triggered) *)
    eState      : ET_SP_VisionState;
    bDone       : BOOL;         (* One-cycle pulse: image fully processed *)
    bErr        : BOOL;         (* Protocol/communication error pulse *)
    uiErr       : UINT;         (* Error code: 1=open,2=timeout,3=send,4=parse *)
    bItemsAvail : BOOL;         (* Parsed items waiting for GetItem *)
    out_stItem  : ST_SP_VisionItem; (* Current item for GetItem *)
END_VAR
VAR
    stCfg    : ST_SP_VisionCfg; (* Configuration (validated by Configure) *)
    m_bCfgOk : BOOL;
    m_Sock   : SP_Socket;       (* TCP adapter *)
    m_sPend  : STRING(240);     (* Response accumulation buffer *)
    m_astIt  : ARRAY[1..16] OF ST_SP_VisionItem; (* Parsed items 1..GC_VIS_MAX *)
    m_iCnt   : SINT := 0;       (* Parsed item count *)
    m_iRd    : SINT := 0;       (* Read index for GetItem *)
    m_bTrigPrev : BOOL;
    m_bSendPulse: BOOL;         (* One-cycle transmit request *)
    m_sTx    : STRING(128);     (* Transmit payload *)
    m_udiSeq : UDINT := 0;      (* {SEQ} macro generator *)
    m_udiTrig: UDINT;           (* Trigger tick [ms] (monotonic) *)
    m_udiLast: UDINT;           (* Last received byte tick [ms] *)
    m_bLineValid : BOOL;        (* m_ParseLine: last consumed line held an item *)
    m_stNew  : ST_SP_VisionItem;(* m_ParseFields: parsed record *)
    m_udiItems : UDINT := 0;    (* Lifetime parsed items *)
    m_udiErrs  : UDINT := 0;    (* Lifetime errors *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
bDone := FALSE;
bErr  := FALSE;
m_bSendPulse := FALSE;

IF NOT m_bCfgOk THEN
    eState := ET_SP_VisionState#Offline;
    RETURN;
END_IF

(* 1) Trigger request build (before socket call, same-cycle atomicity) ----- *)
IF bEnable THEN
    IF bTrig AND NOT m_bTrigPrev THEN
        IF (m_Sock.eState = ET_SP_SocketState#Connected) AND (m_iCnt = 0) THEN
            m_sTx := THIS.BuildTrig();
            m_bSendPulse := TRUE;
            m_iCnt   := 0;
            m_iRd    := 0;
            m_sPend  := '';
            m_udiTrig := udiTickMs;
            m_udiLast := udiTickMs;
            eState   := ET_SP_VisionState#Triggered;
        END_IF
    END_IF
END_IF
m_bTrigPrev := bTrig;

(* 2) Socket service ------------------------------------------------------ *)
m_Sock(
    bOpen    := bEnable,
    sHost    := stCfg.sIp,
    uiPort   := stCfg.uiPort,
    sTx      := m_sTx,
    bSend    := m_bSendPulse,
    tTimeout := stCfg.tTimeout,
    udiTickMs := udiTickMs
);

(* 3) State mapping ------------------------------------------------------- *)
IF NOT bEnable THEN
    eState := ET_SP_VisionState#Offline;
ELSIF m_Sock.eState = ET_SP_SocketState#Fault THEN
    eState := ET_SP_VisionState#Offline;
    uiErr  := UINT#1;
    m_udiErrs := m_udiErrs + 1;
ELSIF m_Sock.eState = ET_SP_SocketState#Connecting THEN
    eState := ET_SP_VisionState#Connecting;
ELSIF eState <> ET_SP_VisionState#Triggered THEN
    eState := ET_SP_VisionState#Online;
END_IF

(* 4) Response supervision (only while waiting) --------------------------- *)
IF (eState = ET_SP_VisionState#Triggered) OR (LEN(m_sPend) > 0) THEN
    IF m_Sock.TakeRx() THEN
        m_sPend  := FUN_SP_VisAppend(m_sPend, m_Sock.out_sRx);
        m_udiLast := udiTickMs;
    END_IF

    IF eState = ET_SP_VisionState#Triggered THEN
        IF THIS.RespComplete(udiTickMs) THEN
            (* Sentinel newline: uniform line extraction *)
            m_sPend := FUN_SP_VisAppend(m_sPend, '$N');
            WHILE m_iCnt < GC_VIS_MAX DO
                IF NOT THIS.m_ParseLine() THEN
                    EXIT;
                END_IF
            END_WHILE

            bDone := TRUE;
            IF m_iCnt > 0 THEN
                eState := ET_SP_VisionState#Online;
                m_udiItems := m_udiItems + SINT_TO_UDINT(m_iCnt);
            ELSE
                bErr  := TRUE;
                uiErr := UINT#4;    (* Nothing parseable in the response *)
                m_udiErrs := m_udiErrs + 1;
                eState := ET_SP_VisionState#Online;
            END_IF
        ELSIF (udiTickMs - m_udiTrig) > TIME_TO_UDINT(stCfg.tTimeout) THEN
            bErr  := TRUE;
            uiErr := UINT#2;        (* Response timeout *)
            m_udiErrs := m_udiErrs + 1;
            m_sPend := '';
            eState  := ET_SP_VisionState#Online;
        END_IF
    END_IF
END_IF

(* 5) Publish ------------------------------------------------------------ *)
bItemsAvail := (m_iCnt > 0) AND (m_iRd < m_iCnt);
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: BuildTrig (parent SP_DrvAscii)
   Compose the trigger payload: template with {SEQ} macro when configured,
   otherwise the plain trigger string; CRLF terminated.
   ----------------------------------------------------------------------- *)
METHOD BuildTrig : STRING(64)
VAR
    (* Position of the {SEQ} macro inside the template *)
    iPos : INT;
    (* Template part left of {SEQ} *)
    sL   : STRING(32);
    (* Template part right of {SEQ} *)
    sR   : STRING(32);
END_VAR
    IF LEN(stCfg.sSendFmt) > 0 THEN
        iPos := FIND(stCfg.sSendFmt, '{SEQ}');
        IF iPos > 0 THEN
            sL := LEFT(stCfg.sSendFmt, iPos - 1);
            sR := RIGHT(stCfg.sSendFmt, LEN(stCfg.sSendFmt) - iPos - 4);
            m_udiSeq := m_udiSeq + 1;
            BuildTrig := CONCAT(sL, CONCAT(FUN_SP_UdToStr(m_udiSeq), sR));
        ELSE
            BuildTrig := stCfg.sSendFmt;
        END_IF
    ELSE
        BuildTrig := stCfg.sTrigStr;
    END_IF
    BuildTrig := CONCAT(BuildTrig, '$R$N');   (* CRLF terminator *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: RespComplete (parent SP_DrvAscii)
   TRUE when the response is considered complete: end token found, idle
   gap exceeded with pending data. Pure decision, no side effects.
   ----------------------------------------------------------------------- *)
METHOD RespComplete : BOOL
VAR_INPUT
    (* Current monotonic tick for the idle-gap decision [ms] *)
    udiTickMs : UDINT;
END_VAR
    RespComplete := FALSE;

    IF (LEN(stCfg.sEndTok) > 0) AND (FIND(m_sPend, stCfg.sEndTok) > 0) THEN
        RespComplete := TRUE;
        RETURN;
    END_IF

    IF (LEN(m_sPend) > 0) AND ((udiTickMs - m_udiLast) > GC_VIS_IDLE) THEN
        RespComplete := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_ParseLine (parent SP_DrvAscii) - internal
   Consume one line from m_sPend (CR or LF delimited). Empty lines are
   consumed without storing. Valid lines are field-parsed and stored.
   Returns TRUE when a line was consumed (caller loops until FALSE).
   ----------------------------------------------------------------------- *)
METHOD m_ParseLine : BOOL
VAR
    (* Position of CR in the pending buffer *)
    iCR  : INT;
    (* Position of LF in the pending buffer *)
    iLF  : INT;
    (* Line-break position inside the pending buffer *)
    iPos : INT;
    (* Line consumed from the pending buffer *)
    sLine: STRING(64);
    (* Pending-buffer length before the cut *)
    iLen : INT;
END_VAR
    m_ParseLine   := FALSE;
    m_bLineValid  := FALSE;

    iCR := FIND(m_sPend, '$R');
    iLF := FIND(m_sPend, '$N');
    iPos := 0;
    IF (iCR > 0) AND (iLF > 0) THEN
        IF iCR < iLF THEN iPos := iCR; ELSE iPos := iLF; END_IF
    ELSIF iCR > 0 THEN
        iPos := iCR;
    ELSIF iLF > 0 THEN
        iPos := iLF;
    END_IF

    IF iPos <= 0 THEN
        RETURN;                     (* No complete line pending *)
    END_IF

    sLine := LEFT(m_sPend, iPos - 1);
    iLen  := LEN(m_sPend);
    m_sPend := RIGHT(m_sPend, iLen - iPos);
    m_ParseLine := TRUE;            (* Line consumed *)

    IF LEN(FUN_SP_Trims(sLine)) = 0 THEN
        RETURN;                     (* Empty line: nothing to store *)
    END_IF

    IF m_iCnt >= GC_VIS_MAX THEN
        RETURN;                     (* Store full: line dropped *)
    END_IF

    IF THIS.m_ParseFields(sLine) THEN
        m_iCnt := m_iCnt + 1;
        m_astIt[m_iCnt] := m_stNew;
        m_bLineValid := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: m_ParseFields (parent SP_DrvAscii) - internal
   Parse one result line into m_stNew using the configured token indexes.
   Applies score threshold and theta normalization (to degrees). TRUE on
   acceptance.
   ----------------------------------------------------------------------- *)
METHOD m_ParseFields : BOOL
VAR_INPUT
    (* Line to field-parse *)
    sLine : STRING(64);
END_VAR
VAR
    (* Parsed product type id (0 = invalid) *)
    uiType : UINT;
    (* Parsed pose fields and score of the line *)
    rX, rY, rTh, rSc : LREAL;
END_VAR
    m_ParseFields := FALSE;

    uiType := FUN_SP_StrToUi(FUN_SP_TokN(sLine, stCfg.sDelim, stCfg.uiIdxType), 0);
    rX  := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, stCfg.sDelim, stCfg.uiIdxX), 0.0);
    rY  := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, stCfg.sDelim, stCfg.uiIdxY), 0.0);
    rTh := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, stCfg.sDelim, stCfg.uiIdxTh), 0.0);
    rSc := FUN_SP_StrToLReal(FUN_SP_TokN(sLine, stCfg.sDelim, stCfg.uiIdxScore), 0.0);

    IF (uiType = 0) OR (uiType > UDINT_TO_UINT(SINT_TO_UDINT(GC_TYPES))) THEN
        RETURN;                     (* Invalid or unclassified result *)
    END_IF
    IF rSc < stCfg.rMinScore THEN
        RETURN;                     (* Below acceptance threshold *)
    END_IF

    IF stCfg.bThInRad THEN
        rTh := FUN_SP_Rad2Deg(rTh);   (* Camera radians -> application degrees *)
    END_IF

    m_stNew.uiTypeId := uiType;
    m_stNew.p2.rX    := rX;
    m_stNew.p2.rY    := rY;
    m_stNew.p2.rTh   := FUN_SP_NormAng(rTh);
    m_stNew.rScore   := rSc;
    m_stNew.rWeight  := 0.0;
    m_stNew.rBeltPos := rBeltPos;
    m_stNew.bTarget  := FALSE;
    m_stNew.bValid   := TRUE;
    m_ParseFields := TRUE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetItem (parent SP_DrvAscii)
   Sequential accessor over the parsed items of the last image.
   TRUE while an item was copied into out_stItem; FALSE when exhausted
   (callers stop polling on FALSE).
   ----------------------------------------------------------------------- *)
METHOD GetItem : BOOL
    IF m_iRd < m_iCnt THEN
        m_iRd := m_iRd + 1;
        out_stItem := m_astIt[m_iRd];
        GetItem := TRUE;
        IF m_iRd >= m_iCnt THEN
            bItemsAvail := FALSE;
        END_IF
    ELSE
        m_iCnt := 0;
        m_iRd  := 0;
        bItemsAvail := FALSE;
        GetItem := FALSE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ClearItems (parent SP_DrvAscii)
   Drop parsed items (used by the manager after a harvest abort).
   ----------------------------------------------------------------------- *)
METHOD ClearItems : UDINT
    ClearItems := SINT_TO_UDINT(m_iCnt);  (* Discarded items *)
    m_iCnt := 0;
    m_iRd  := 0;
    bItemsAvail := FALSE;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Configure (parent SP_DrvAscii)
   Validate and store the driver configuration.
   ----------------------------------------------------------------------- *)
METHOD Configure : ET_SP_RetCode
VAR_INPUT
    (* Configuration record to validate and store *)
    stIn : ST_SP_VisionCfg;
END_VAR
    Configure := ET_SP_RetCode#Done;

    IF LEN(stIn.sDelim) = 0 THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF (stIn.uiIdxType < UINT#1) OR (stIn.uiIdxX < UINT#1) OR (stIn.uiIdxY < UINT#1)
          OR (stIn.uiIdxTh < UINT#1) OR (stIn.uiIdxScore < UINT#1) THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF (stIn.uiPort = 0) OR (LEN(stIn.sIp) = 0) THEN
        Configure := ET_SP_RetCode#ErrParam;
    ELSIF stIn.uiMaxItems > UDINT_TO_UINT(SINT_TO_UDINT(GC_VIS_MAX)) THEN
        Configure := ET_SP_RetCode#ErrRange;
    ELSE
        stCfg    := stIn;
        m_bCfgOk := TRUE;
    END_IF
END_METHOD
