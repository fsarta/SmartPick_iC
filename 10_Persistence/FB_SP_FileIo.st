(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 10_Persistence
   Worksheet : FB - SP_FileIo
   -----------------------------------------------------------------------------
   Purpose   : FIRMWARE ADAPTER - ASCII file access for recipe export/import
               and log dumps.

   No pointer types or ADR() operators are used in user code; buffers are
   passed directly to the firmware file adapter.

   FW BINDING (CONFIRM signatures against the installed SysLibFile):
     hFile := SysFileOpen(szFile, eMode)
     udiGot:= SysFileRead(hFile, m_abBuf, iWant)
     udiPut:= SysFileWrite(hFile, sOut, LEN(sOut))
     SysFileClose(hFile)
   Read protocol: bytes accumulate into a pending line buffer; lines are
   published one per cycle when a CR/LF terminator is found.
   =============================================================================
*)

FUNCTION_BLOCK SP_FileIo
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    bCloseReq : BOOL;           (* TRUE = close the open file *)
END_VAR
VAR_OUTPUT
    (* File operation lifecycle (Idle/Reading/Writing/Done/Error) *)
    eState : ET_SP_FileState;
    (* Last file error code (firmware / adapter specific) *)
    uiErr  : UINT;
    bLineRdy: BOOL;             (* A line is available in out_sLine *)
    out_sLine: STRING(200);     (* Last read line *)
END_VAR
VAR
    (* Firmware file handle (0 = closed) *)
    m_hFile : UDINT := UDINT#0;
    (* TRUE = write mode open, FALSE = read mode *)
    m_bWrite: BOOL;
    (* Raw byte buffer bound to the firmware API *)
    m_abBuf : ARRAY[1..512] OF BYTE;
    m_sPend : STRING(240);      (* Pending line accumulation *)
    m_bEof  : BOOL;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF bCloseReq AND (eState <> ET_SP_FileState#Closed) THEN
    THIS.CloseNow();
    RETURN;
END_IF

IF (eState = ET_SP_FileState#Open) AND (NOT m_bWrite) THEN
    THIS.ReadStep();
END_IF
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: OpenWrite (parent SP_FileIo)
   Open a text file for writing (truncate). TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD OpenWrite : BOOL
VAR_INPUT
    (* Absolute file path to open for writing *)
    sPath : STRING(64);
END_VAR
    THIS.CloseNow();
    (* CONFIRM: SysFileOpen signature/mode enum of the target library *)
    m_hFile := SysFileOpen(sPath, UDINT#1);   (* 1 = write mode (CONFIRM) *)
    OpenWrite := (m_hFile <> UDINT#0);
    IF OpenWrite THEN
        m_bWrite := TRUE;
        eState := ET_SP_FileState#Open;
    ELSE
        uiErr := UINT#1;
        eState := ET_SP_FileState#Fault;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: OpenRead (parent SP_FileIo)
   Open a text file for reading. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD OpenRead : BOOL
VAR_INPUT
    (* Absolute file path to open for reading *)
    sPath : STRING(64);
END_VAR
    THIS.CloseNow();
    (* CONFIRM: SysFileOpen signature/mode enum of the target library *)
    m_hFile := SysFileOpen(sPath, UDINT#0);   (* 0 = read mode (CONFIRM) *)
    OpenRead := (m_hFile <> UDINT#0);
    IF OpenRead THEN
        m_bWrite := FALSE;
        m_sPend := '';
        m_bEof := FALSE;
        eState := ET_SP_FileState#Open;
    ELSE
        uiErr := UINT#1;
        eState := ET_SP_FileState#Fault;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: WriteLine (parent SP_FileIo)
   Write one ASCII line (CR terminated). TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD WriteLine : BOOL
VAR_INPUT
    (* Line to append (CRLF added by the adapter) *)
    sLine : STRING(200);
END_VAR
VAR
    (* Bytes actually written by the firmware call *)
    udiPut : UDINT;
    (* Line normalized to CRLF termination *)
    sOut : STRING(202);
END_VAR
    WriteLine := FALSE;
    IF (eState <> ET_SP_FileState#Open) OR (NOT m_bWrite) THEN
        RETURN;
    END_IF
    sOut := CONCAT(sLine, '$R');
    (* CONFIRM: SysFileWrite signature *)
    udiPut := SysFileWrite(m_hFile, sOut, INT_TO_UDINT(LEN(sOut)));
    WriteLine := (udiPut = INT_TO_UDINT(LEN(sOut)));
    IF NOT WriteLine THEN
        uiErr := UINT#2;
        eState := ET_SP_FileState#Fault;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: CloseNow (parent SP_FileIo) - internal
   ----------------------------------------------------------------------- *)
METHOD CloseNow : BOOL
    CloseNow := TRUE;               (* Close executed *)
    IF m_hFile <> UDINT#0 THEN
        SysFileClose(m_hFile);      (* CONFIRM: signature *)
        m_hFile := UDINT#0;
    END_IF
    eState := ET_SP_FileState#Closed;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ReadStep (parent SP_FileIo) - internal
   Pull bytes from the firmware, accumulate the pending line, publish one
   complete line per call (CR/LF terminated). At EOF the pending tail is
   flushed as the final line.
   ----------------------------------------------------------------------- *)
METHOD ReadStep : BOOL
VAR
    (* Bytes read by the firmware call this cycle *)
    udiGot : UDINT;
    (* Byte loop index (buffer to string) *)
    i : INT;
    (* Line-break search position *)
    iPos : INT;
    (* Accumulated byte count *)
    iLen : INT;
    (* String view of the raw bytes read *)
    sChunk : STRING(200);
    (* One printable character of the chunk *)
    sCh : STRING(1);
    (* Line assembled from the raw bytes *)
    sLine : STRING(200);
END_VAR
    ReadStep := FALSE;              (* Default: no line this cycle *)
    bLineRdy := FALSE;

    (* 1) Refill the pending buffer *)
    IF (NOT m_bEof) AND (LEN(m_sPend) < 128) THEN
        udiGot := SysFileRead(m_hFile, m_abBuf, UDINT#128);  (* CONFIRM *)
        IF udiGot = UDINT#0 THEN
            m_bEof := TRUE;
        ELSE
            sChunk := '';
            FOR i := 1 TO UDINT_TO_INT(udiGot) DO
                sChunk := CONCAT(sChunk, FUN_SP_ByteCh(m_abBuf[i]));
            END_FOR
            m_sPend := FUN_SP_VisAppend(m_sPend, sChunk);
        END_IF
    END_IF

    (* 2) Extract a complete line when available *)
    iLen := LEN(m_sPend);
    iPos := 0;
    FOR i := 1 TO iLen DO
        sCh := MID(m_sPend, 1, i);
        IF (sCh = '$R') OR (sCh = '$N') THEN
            iPos := i;
            EXIT;
        END_IF
    END_FOR

    IF iPos > 0 THEN
        IF iPos > 1 THEN
            sLine := MID(m_sPend, iPos - 1, 1);
        ELSE
            sLine := '';
        END_IF
        m_sPend := RIGHT(m_sPend, iLen - iPos);
        out_sLine := FUN_SP_Trims(sLine);
        bLineRdy := TRUE;
        ReadStep := TRUE;
    ELSIF m_bEof AND (iLen > 0) THEN
        (* Final unterminated line *)
        out_sLine := FUN_SP_Trims(m_sPend);
        m_sPend := '';
        bLineRdy := TRUE;
        ReadStep := TRUE;
    END_IF
END_METHOD
