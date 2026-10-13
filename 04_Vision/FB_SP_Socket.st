(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : FB - SP_Socket
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE ADAPTER - non-blocking TCP client for camera drivers.
               State machine: Closed -> Connecting -> Connected / Fault.
               Receive path: firmware writes raw bytes into a temporary
               buffer; bytes are appended to the accumulation buffer and
               mirrored into a string view for the ASCII drivers.

   *** POINTERS POLICY (single documented deviation) ***
   The firmware socket API (SysSocket family) requires address parameters.
   ADR() is used HERE ONLY, on internal buffers, exclusively to satisfy the
   firmware call signatures. No pointer types are declared anywhere in the
   SmartPick library and no pointer leaves this FB. SysFile binding follows
   the same pattern inside SP_FileIo. This is the reference pattern for
   SysSocket/SysFile binding on iCube Engineer.

   FW BINDING (CONFIRM signatures against the installed SysLibSocket):
     hSock  := SysSocketOpen(sHost, uiPort)
     uiSent := SysSocketSend(hSock, sTx, INT_TO_UDINT(LEN(sTx)))
     uiGot  := SysSocketReceive(hSock, m_abTmp, iWant)
     SysSocketClose(hSock)
   =============================================================================
*)

FUNCTION_BLOCK SP_Socket
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bOpen   : BOOL;           (* TRUE = connection desired *)
    sHost   : STRING(16);     (* Remote IP *)
    uiPort  : UINT;           (* Remote port *)
    sTx     : STRING(128);    (* Payload to transmit *)
    bSend   : BOOL;           (* Rising edge: transmit sTx *)
    tTimeout: TIME;           (* Connection timeout *)
    udiTickMs : UDINT;        (* Monotonic ms tick (GVL_SP_Rtc, v1.8.0) *)
END_VAR
VAR_OUTPUT
    (* Socket lifecycle (Closed/Connecting/Connected/Fault) *)
    eState  : ET_SP_SocketState;
    bConn   : BOOL;           (* TRUE when Connected *)
    uiErr   : UINT;           (* Last socket error code *)
    out_sRx : STRING(255);    (* Drained payload (filled by TakeRx) *)
END_VAR
VAR
    m_hSock   : UDINT;        (* Socket handle (opaque firmware token) *)
    m_abRx    : ARRAY[1..512] OF BYTE;  (* Accumulated receive data 1..GC_SOCK_RX *)
    m_abTmp   : ARRAY[1..512] OF BYTE;  (* Firmware receive target 1..GC_SOCK_RX *)
    m_sView   : STRING(255);  (* String view of accumulated bytes *)
    m_uiRxLen : UINT;         (* Bytes pending *)
    m_bRxDrop : BOOL;         (* Overflow diagnostic flag *)
    m_uiSent  : UDINT;        (* Bytes sent confirmation *)
    m_udiConn : UDINT;        (* Connection attempt tick [ms] *)
    m_bSendPrev : BOOL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* 0) Global off / reset -------------------------------------------------- *)
IF NOT bOpen THEN
    IF eState <> ET_SP_SocketState#Closed THEN
        SysSocketClose(m_hSock);       (* CONFIRM: signature *)
        m_hSock   := UDINT#0;
        m_uiRxLen := UINT#0;
        eState    := ET_SP_SocketState#Closed;
    END_IF
    bConn := FALSE;
    m_bSendPrev := bSend;
    RETURN;
END_IF

(* 1) Closed / Fault -> Connecting ---------------------------------------- *)
IF (eState = ET_SP_SocketState#Closed) OR (eState = ET_SP_SocketState#Fault) THEN
    IF eState = ET_SP_SocketState#Fault THEN
        SysSocketClose(m_hSock);       (* Clean previous handle *)
        m_hSock := UDINT#0;
    END_IF
    m_hSock := SysSocketOpen(sHost, uiPort);   (* CONFIRM: signature *)
    IF m_hSock = UDINT#0 THEN
        eState := ET_SP_SocketState#Fault;
        uiErr  := UINT#1;              (* Open failed *)
        bConn  := FALSE;
        RETURN;
    END_IF
    m_udiConn := udiTickMs;
    eState   := ET_SP_SocketState#Connecting;
    RETURN;
END_IF

(* 2) Connecting supervision ---------------------------------------------- *)
IF eState = ET_SP_SocketState#Connecting THEN
    (* Embedded stacks typically connect synchronously at open; the
       timeout only guards semi-open implementations. Monotonic tick
       difference: wrap-safe unsigned subtraction (v1.8.0). *)
    IF (udiTickMs - m_udiConn) > TIME_TO_UDINT(tTimeout) THEN
        eState := ET_SP_SocketState#Fault;
        uiErr  := UINT#2;              (* Connect timeout *)
        bConn  := FALSE;
        RETURN;
    END_IF
    eState := ET_SP_SocketState#Connected;
END_IF

(* 3) Connected: transmit on edge, then poll receive ----------------------- *)
IF eState = ET_SP_SocketState#Connected THEN
    bConn := TRUE;

    IF bSend AND NOT m_bSendPrev THEN
        m_uiSent := SysSocketSend(m_hSock, sTx, INT_TO_UDINT(LEN(sTx)));  (* CONFIRM *)
        IF m_uiSent <> INT_TO_UDINT(LEN(sTx)) THEN
            eState := ET_SP_SocketState#Fault;
            uiErr  := UINT#3;          (* Send failed / partial *)
            bConn  := FALSE;
        END_IF
    END_IF
    m_bSendPrev := bSend;

    IF eState = ET_SP_SocketState#Connected THEN
        THIS.PollRx();
    END_IF
END_IF
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: PollRx (parent SP_Socket)
   Non-blocking firmware receive into m_abTmp, append into m_abRx and
   refresh the string view. Called by the FB body only (firmware call is
   intentionally NOT exposed to methods or callers).
   ----------------------------------------------------------------------- *)
METHOD PollRx : BOOL
VAR
    (* Bytes received this cycle (0 = nothing) *)
    uiGot : UDINT;
    (* Byte copy loop index *)
    i     : UINT;
    (* Free space offered to the firmware receive call *)
    iWant : DINT;
    (* One printable character of the string view *)
    sCh   : STRING(1);
    (* Bytes mirrored into the string view (capped at 200) *)
    uiLim : UINT;
    (* Remaining room in the accumulation buffer *)
    iSpace: DINT;
END_VAR
    PollRx := FALSE;                (* Default: nothing received *)
    iWant := GC_SOCK_RX - 1;
    IF m_uiRxLen > 0 THEN
        iWant := iWant - UINT_TO_DINT(m_uiRxLen);
    END_IF
    IF iWant < 1 THEN
        m_bRxDrop := TRUE;             (* Caller must drain (TakeRx) *)
        RETURN;
    END_IF

    uiGot := SysSocketReceive(m_hSock, m_abTmp, iWant);   (* CONFIRM: signature *)
    IF uiGot = UDINT#0 THEN
        RETURN;                        (* Nothing this cycle *)
    END_IF
    PollRx := TRUE;                    (* Bytes received this cycle *)

    (* Append firmware bytes into the accumulation buffer *)
    iSpace := GC_SOCK_RX - 1 - UINT_TO_DINT(m_uiRxLen);
    FOR i := 1 TO UDINT_TO_UINT(uiGot) DO
        IF UINT_TO_DINT(i) > iSpace THEN
            m_bRxDrop := TRUE;         (* Buffer full: drop excess *)
            EXIT;
        END_IF
        m_abRx[m_uiRxLen + i] := m_abTmp[i];
    END_FOR
    IF m_bRxDrop THEN
        m_uiRxLen := DINT_TO_UINT(GC_SOCK_RX - 1);
    ELSE
        m_uiRxLen := m_uiRxLen + UDINT_TO_UINT(uiGot);
    END_IF

    (* Refresh the string view from accumulated printable bytes *)
    m_sView := '';
    uiLim   := m_uiRxLen;
    IF uiLim > 200 THEN
        uiLim := 200;                  (* STRING(255) headroom *)
    END_IF
    FOR i := 1 TO uiLim DO
        sCh    := FUN_SP_ByteCh(m_abRx[i]);
        m_sView:= CONCAT(m_sView, sCh);
    END_FOR
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: TakeRx (parent SP_Socket)
   Atomically drain the receive buffer: copies the string view into the
   public out_sRx member and clears the accumulation. TRUE when data was
   pending. Pure buffer handling: no firmware calls (method safe).
   ----------------------------------------------------------------------- *)
METHOD TakeRx : BOOL
    TakeRx := FALSE;
    IF m_uiRxLen > 0 THEN
        out_sRx   := m_sView;
        m_uiRxLen := 0;
        m_bRxDrop := FALSE;
        TakeRx := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: RxCount (parent SP_Socket)
   Bytes pending in the accumulation buffer.
   ----------------------------------------------------------------------- *)
METHOD RxCount : UINT
    RxCount := m_uiRxLen;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: RxOverflow (parent SP_Socket)
   TRUE when bytes were dropped due to a full buffer (diagnostic).
   ----------------------------------------------------------------------- *)
METHOD RxOverflow : BOOL
    RxOverflow := m_bRxDrop;
END_METHOD
