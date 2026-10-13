(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION - FUN_SP_ByteCh
   -----------------------------------------------------------------------------
   Purpose   : Convert a received byte (32..126) into a one-character string
               using the printable ASCII lookup table. Bytes outside the
               printable range are mapped to '.'.
               This keeps all socket traffic handling free of pointer types
               in user code (bytes -> string conversion is table based).
   =============================================================================
*)

FUNCTION FUN_SP_ByteCh : STRING(1)
VAR_INPUT
    (* Byte code received from the socket (ASCII expected) *)
    byVal : BYTE;
END_VAR
VAR
    (* Index into the printable-ASCII lookup table GC_ASCII95 *)
    iPos : DINT;
END_VAR
    iPos := BYTE_TO_DINT(byVal) - 31;
    IF (iPos >= 1) AND (iPos <= 95) THEN
        FUN_SP_ByteCh := MID(GC_ASCII95, 1, iPos);
    ELSE
        FUN_SP_ByteCh := '.';
    END_IF
END_FUNCTION
