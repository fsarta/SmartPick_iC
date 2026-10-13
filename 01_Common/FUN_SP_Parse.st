(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION(s) - FUN_SP_Parse
   -----------------------------------------------------------------------------
   Purpose   : ASCII tokenization and numeric conversion helpers used by:
               - Vision drivers (result line parsing)
               - Recipe import/export (key=value parsing)
               - Logger/alarm text formatting
               All parsers are self-contained (no vendor conversion
               functions) to guarantee identical behavior on any target.
   -----------------------------------------------------------------------------
   Constraints: Functions use VAR and VAR_INPUT only, no pointers,
               no recursion, no dynamic memory.
   =============================================================================
*)


(* -----------------------------------------------------------------------------
   FUN_SP_TokN : Return the n-th token (1-based) of sTxt split by sDelim.
               Returns '' when the token does not exist.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_TokN : STRING(64)
VAR_INPUT
    (* Input line to tokenize *)
    sTxt   : STRING(255);
    (* Single-character field delimiter *)
    sDelim : STRING(1);
    uiN    : UINT;      (* 1-based token index *)
END_VAR
VAR
    (* Unconsumed tail of the input while scanning tokens *)
    sRest  : STRING(255);
    (* Flag: at least one delimiter was seen *)
    iFound : SINT;
    (* Token loop counter (1..uiN) *)
    uiK    : UINT;
    (* Character position in the allowed-charset table *)
    iPos   : SINT;
    (* Delimiter position copied for LEN arithmetic *)
    uiNdx  : UINT;
    (* Token extracted for the requested index *)
    sTok   : STRING(64);
END_VAR
    sTok   := '';
    sRest  := sTxt;
    iFound := 0;
    IF (uiN >= 1) AND (LEN(sDelim) > 0) THEN
        FOR uiK := 1 TO uiN DO
            iPos := FIND(sRest, sDelim);
            IF iPos > 0 THEN
                IF uiK = uiN THEN
                    sTok := LEFT(sRest, iPos - 1);
                ELSE
                    uiNdx := iPos;                       (* avoid arith on LEN arg *)
                    sRest := RIGHT(sRest, LEN(sRest) - uiNdx);
                END_IF
            ELSE
                IF uiK = uiN THEN
                    sTok := sRest;
                END_IF
                EXIT;
            END_IF
            iFound := 1;
        END_FOR
    END_IF
    FUN_SP_TokN := FUN_SP_Trims(sTok);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_TokCnt : Number of tokens in sTxt when split by sDelim (>=1).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_TokCnt : UINT
VAR_INPUT
    (* Input line to tokenize *)
    sTxt   : STRING(255);
    (* Single-character field delimiter *)
    sDelim : STRING(1);
END_VAR
VAR
    (* Unconsumed tail while counting tokens *)
    sRest  : STRING(255);
    (* Token counter (starts at 1: a line is always one token) *)
    uiCnt  : UINT;
    (* Character position in the allowed-charset table *)
    iPos   : SINT;
    (* Delimiter position copied for LEN arithmetic *)
    uiNdx  : UINT;
END_VAR
    uiCnt := 0;
    sRest := sTxt;
    IF LEN(sDelim) > 0 THEN
        uiCnt := 1;
        WHILE TRUE DO
            iPos := FIND(sRest, sDelim);
            IF iPos <= 0 THEN
                EXIT;
            END_IF
            uiCnt := uiCnt + 1;
            uiNdx := iPos;
            sRest := RIGHT(sRest, LEN(sRest) - uiNdx);
        END_WHILE
    END_IF
    FUN_SP_TokCnt := uiCnt;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Trims : Trim leading and trailing spaces of sTxt.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Trims : STRING(64)
VAR_INPUT
    (* String to trim *)
    sTxt : STRING(64);
END_VAR
VAR
    (* Length of the concatenation result *)
    iLen : SINT;
    (* First non-space position *)
    iSt  : SINT;
    (* Last non-space position *)
    iEn  : SINT;
    (* Character loop index (trim scan) *)
    i    : SINT;
    (* Character under examination *)
    sCh  : STRING(1);
END_VAR
    iLen := LEN(sTxt);
    iSt  := 1;
    iEn  := iLen;

    FOR i := 1 TO iLen DO
        sCh := MID(sTxt, 1, i);
        IF sCh <> ' ' THEN
            iSt := i;
            EXIT;
        END_IF
    END_FOR

    FOR i := iLen TO 1 BY -1 DO
        sCh := MID(sTxt, 1, i);
        IF sCh <> ' ' THEN
            iEn := i;
            EXIT;
        END_IF
    END_FOR

    IF iEn >= iSt THEN
        FUN_SP_Trims := MID(sTxt, iEn - iSt + 1, iSt);
    ELSE
        FUN_SP_Trims := '';
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_StrToLReal : Parse a decimal LREAL (optional sign, '.', exponent).
               Returns rDefault when parsing fails.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_StrToLReal : LREAL
VAR_INPUT
    (* Text to parse as decimal LREAL *)
    sTxt     : STRING(32);
    (* Value returned when parsing fails *)
    rDefault : LREAL;
END_VAR
VAR
    (* Trimmed working copy of the input *)
    s        : STRING(32);
    (* Length of the concatenation result *)
    iLen     : SINT;
    (* Character loop index (LReal parse) *)
    i        : SINT;
    (* Character under examination *)
    sCh      : STRING(1);
    (* Sign factor (-1.0 / +1.0) *)
    rSign    : LREAL;
    (* Accumulated integer part *)
    rInt     : LREAL;
    (* Accumulated fractional part *)
    rFrac    : LREAL;
    (* Fractional divider (10^number_of_decimals) *)
    rDiv     : LREAL;
    (* Accumulated exponent digits *)
    rExp     : LREAL;
    (* Exponent sign (-1 / +1) *)
    iExpSgn  : SINT;
    ePhase   : SINT;   (* 0=int 1=frac 2=exp *)
    bDigit   : BOOL;
    (* Numeric value of the current digit (0..9) *)
    iD       : SINT;
END_VAR
    FUN_SP_StrToLReal := rDefault;
    s    := FUN_SP_Trims(sTxt);
    iLen := LEN(s);
    IF (iLen = 0) OR (iLen > 24) THEN
        RETURN;
    END_IF

    rSign := 1.0;  rInt := 0.0;  rFrac := 0.0;  rDiv := 1.0;
    rExp  := 0.0;  iExpSgn := 1;  ePhase := 0;

    FOR i := 1 TO iLen DO
        sCh := MID(s, 1, i);
        IF (i = 1) AND (sCh = '-') THEN
            rSign := -1.0;
        ELSIF (i = 1) AND (sCh = '+') THEN
            (* sign positive, nothing to do *)
        ELSIF (sCh = '.') AND (ePhase = 0) THEN
            ePhase := 1;
        ELSIF ((sCh = 'e') OR (sCh = 'E')) AND (ePhase < 2) THEN
            ePhase := 2;
        ELSIF (ePhase = 2) AND (sCh = '-') THEN
            iExpSgn := -1;
        ELSIF (ePhase = 2) AND (sCh = '+') THEN
            (* exponent sign positive *)
        ELSE
            iD := FUN_SP_DigVal(sCh);
            bDigit := (iD >= 0);
            IF NOT bDigit THEN
                RETURN; (* invalid character -> default *)
            END_IF
            IF ePhase = 0 THEN
                rInt := rInt * 10.0 + UDINT_TO_LREAL(SINT_TO_UDINT(iD));
            ELSIF ePhase = 1 THEN
                rDiv  := rDiv * 10.0;
                rFrac := rFrac + UDINT_TO_LREAL(SINT_TO_UDINT(iD)) / rDiv;
            ELSE
                rExp := rExp * 10.0 + UDINT_TO_LREAL(SINT_TO_UDINT(iD));
            END_IF
        END_IF
    END_FOR

    IF rExp > 0.0 THEN
        FUN_SP_StrToLReal := rSign * (rInt + rFrac) * EXPT(10.0, iExpSgn * rExp);
    ELSE
        FUN_SP_StrToLReal := rSign * (rInt + rFrac);
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_StrToUi : Parse an unsigned integer (digits only). Default on error.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_StrToUi : UINT
VAR_INPUT
    (* Digits-only text to convert (UINT) *)
    sTxt     : STRING(16);
    (* Value returned when parsing fails *)
    uiDefault: UINT;
END_VAR
VAR
    (* Character loop index (StrToUi) *)
    i    : SINT;
    (* Length of the concatenation result *)
    iLen : SINT;
    (* Character under examination *)
    sCh  : STRING(1);
    (* Numeric value of the current digit (0..9) *)
    iD   : SINT;
    (* Accumulated integer result *)
    udi  : UDINT;
END_VAR
    FUN_SP_StrToUi := uiDefault;
    iLen := LEN(sTxt);
    IF (iLen = 0) OR (iLen > 9) THEN
        RETURN;
    END_IF
    udi := 0;
    FOR i := 1 TO iLen DO
        sCh := MID(sTxt, 1, i);
        iD  := FUN_SP_DigVal(sCh);
        IF iD < 0 THEN
            RETURN;
        END_IF
        udi := udi * 10 + SINT_TO_UDINT(iD);
    END_FOR
    FUN_SP_StrToUi := UDINT_TO_UINT(udi);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_StrToUd : Parse an unsigned 32-bit integer (digits only).
               Default on error. Needed for values beyond the UINT range
               (recipe type masks, batch quantities, ms timeouts).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_StrToUd : UDINT
VAR_INPUT
    (* Digits-only text to convert (UDINT) *)
    sTxt     : STRING(16);
    (* Value returned when parsing fails *)
    udiDefault: UDINT;
END_VAR
VAR
    (* Character loop index (StrToUd) *)
    i    : SINT;
    (* Length of the concatenation result *)
    iLen : SINT;
    (* Character under examination *)
    sCh  : STRING(1);
    (* Numeric value of the current digit (0..9) *)
    iD   : SINT;
    (* Accumulated integer result *)
    udi  : UDINT;
END_VAR
    FUN_SP_StrToUd := udiDefault;
    iLen := LEN(sTxt);
    IF (iLen = 0) OR (iLen > 10) THEN
        RETURN;
    END_IF
    udi := 0;
    FOR i := 1 TO iLen DO
        sCh := MID(sTxt, 1, i);
        iD  := FUN_SP_DigVal(sCh);
        IF iD < 0 THEN
            RETURN;
        END_IF
        udi := udi * 10 + SINT_TO_UDINT(iD);
    END_FOR
    FUN_SP_StrToUd := udi;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_UiToStr : Format an unsigned integer as decimal string.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_UiToStr : STRING(16)
VAR_INPUT
    (* Value to format as decimal text *)
    uiVal : UINT;
END_VAR
VAR
    (* Working copy of the value *)
    udi   : UDINT;
    (* Digit string under construction *)
    s     : STRING(16);
    (* Numeric value of the current digit (0..9) *)
    iD    : SINT;
END_VAR
    s   := '';
    udi := UINT_TO_UDINT(uiVal);
    IF udi = 0 THEN
        FUN_SP_UiToStr := '0';
        RETURN;
    END_IF
    WHILE udi > 0 DO
        iD := UDINT_TO_SINT(udi MOD 10);
        s  := CONCAT(FUN_SP_DigCh(iD), s);
        udi := udi / 10;
    END_WHILE
    FUN_SP_UiToStr := s;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_LRealToStr : Format a LREAL with fixed decimals (0..6), no exponent.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_LRealToStr : STRING(24)
VAR_INPUT
    (* Value to format *)
    rVal : LREAL;
    iDec : SINT;    (* number of decimal digits, 0..6 *)
END_VAR
VAR
    (* Absolute working copy of rVal *)
    rV   : LREAL;
    (* TRUE when the input value is negative *)
    bNeg : BOOL;
    (* Integer part digits (rounded up on overflow) *)
    udiI : UDINT;
    (* Fractional digits scaled by 10^iDec *)
    udiF : UDINT;
    (* Scale factor 10^iDec *)
    udiS : UDINT;
    (* Formatted integer part *)
    sI   : STRING(16);
    (* Formatted fractional part (with dot) *)
    sF   : STRING(8);
    (* Scale-factor loop index *)
    iK   : SINT;
    (* Numeric value of the current digit (0..9) *)
    iD   : SINT;
END_VAR
    rV   := rVal;
    bNeg := (rV < 0.0);
    IF bNeg THEN
        rV := -rV;
    END_IF

    iDec := FUN_SP_ClampI(iDec, 0, 6);
    udiS := 1;
    FOR iK := 1 TO iDec DO
        udiS := udiS * 10;
    END_FOR

    udiI := LREAL_TO_UDINT(TRUNC(rV));
    udiF := LREAL_TO_UDINT(TRUNC((rV - TRUNC(rV)) * UDINT_TO_LREAL(udiS) + 0.5));

    (* Rounding overflow: 1.999 with 2 dec -> udiF = 1000 *)
    IF udiF >= udiS THEN
        udiI := udiI + 1;
        udiF := udiF - udiS;
    END_IF

    (* Build integer part (max 9 digits for safety) *)
    sI := '';
    IF udiI = 0 THEN
        sI := '0';
    ELSE
        WHILE udiI > 0 DO
            iD := UDINT_TO_SINT(udiI MOD 10);
            sI := CONCAT(FUN_SP_DigCh(iD), sI);
            udiI := udiI / 10;
        END_WHILE
    END_IF

    (* Build fractional part *)
    sF := '';
    IF iDec > 0 THEN
        sF := '.';
        FOR iK := iDec TO 1 BY -1 DO
            iD  := UDINT_TO_SINT(udiF MOD 10);
            sF  := CONCAT(FUN_SP_DigCh(iD), sF);
            udiF := udiF / 10;
        END_FOR
    END_IF

    IF bNeg THEN
        sI := CONCAT('-', sI);
    END_IF

    FUN_SP_LRealToStr := CONCAT(sI, sF);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_VisAppend : Append a chunk to a bounded accumulation buffer.
               When the result exceeds uiKeep characters, the OLDEST part
               is dropped (sliding window) so the newest response data is
               always retained for parsing.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_VisAppend : STRING(240)
VAR_INPUT
    sBuf   : STRING(240);   (* Current accumulation *)
    sChunk : STRING(255);   (* Data to append *)
END_VAR
VAR
    (* Concatenation of buffer and new chunk *)
    sAll   : STRING(255);
    (* Length of the concatenation result *)
    iLen   : SINT;
END_VAR
    sAll := CONCAT(sBuf, sChunk);
    iLen := LEN(sAll);
    IF iLen > 240 THEN
        FUN_SP_VisAppend := RIGHT(sAll, 200);   (* Keep newest 200 chars *)
    ELSE
        FUN_SP_VisAppend := sAll;
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_StrSum : Additive checksum of a string (portability CRC substitute
               for retain validation). Not cryptographic, by design.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_StrSum : UDINT
VAR_INPUT
    (* Text whose additive checksum is computed *)
    sTxt : STRING(120);
END_VAR
VAR
    (* Character loop index (checksum) *)
    i    : SINT;
    (* Length of the concatenation result *)
    iLen : SINT;
    (* Accumulated checksum *)
    udi  : UDINT;
    (* Character under examination *)
    sCh  : STRING(1);
    (* Character position in the allowed-charset table *)
    iPos : SINT;
END_VAR
    udi  := 0;
    iLen := LEN(sTxt);
    FOR i := 1 TO iLen DO
        sCh  := MID(sTxt, 1, i);
        iPos := FIND('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-_:=,;/[] ', sCh);
        IF iPos > 0 THEN
            udi := udi + SINT_TO_UDINT(iPos) + UDINT#31 * SINT_TO_UDINT(i);
        ELSE
            udi := udi + UDINT#127;
        END_IF
    END_FOR
    FUN_SP_StrSum := udi;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_UdToStr : Format an UDINT as decimal string (32-bit safe).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_UdToStr : STRING(16)
VAR_INPUT
    (* 32-bit value to format as decimal text *)
    udiVal : UDINT;
END_VAR
VAR
    (* Working copy of the value *)
    udi   : UDINT;
    (* Formatted output under construction *)
    s     : STRING(16);
    (* Numeric value of the current digit (0..9) *)
    iD    : SINT;
END_VAR
    udi := udiVal;
    IF udi = UDINT#0 THEN
        FUN_SP_UdToStr := '0';
        RETURN;
    END_IF
    s := '';
    WHILE udi > UDINT#0 DO
        iD := UDINT_TO_SINT(udi MOD UDINT#10);
        s  := CONCAT(FUN_SP_DigCh(iD), s);
        udi := udi / UDINT#10;
    END_WHILE
    FUN_SP_UdToStr := s;
END_FUNCTION
