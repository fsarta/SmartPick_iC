(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FUNCTION(s) - FUN_SP_Utils
   -----------------------------------------------------------------------------
   Purpose   : Small pure helper functions used across all modules.
               If the tool requires one FUNCTION per worksheet, split each
               FUNCTION block into its own worksheet keeping exact names.
   -----------------------------------------------------------------------------
   Constraints: Functions use VAR and VAR_INPUT only (no VAR_IN_OUT,
               no VAR_OUTPUT), no pointers, no recursion, no globals.
   =============================================================================
*)


(* -----------------------------------------------------------------------------
   FUN_SP_Clamp : Constrain a LREAL value into [rLo, rHi].
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Clamp : LREAL
VAR_INPUT
    (* Value to constrain *)
    rVal : LREAL;
    (* Lower bound *)
    rLo  : LREAL;
    (* Upper bound *)
    rHi  : LREAL;
END_VAR
    IF rVal < rLo THEN
        FUN_SP_Clamp := rLo;
    ELSIF rVal > rHi THEN
        FUN_SP_Clamp := rHi;
    ELSE
        FUN_SP_Clamp := rVal;
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_ClampI : Constrain a DINT value into [iLo, iHi].
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_ClampI : DINT
VAR_INPUT
    (* Value to constrain *)
    iVal : DINT;
    (* Lower bound *)
    iLo  : DINT;
    (* Upper bound *)
    iHi  : DINT;
END_VAR
    IF iVal < iLo THEN
        FUN_SP_ClampI := iLo;
    ELSIF iVal > iHi THEN
        FUN_SP_ClampI := iHi;
    ELSE
        FUN_SP_ClampI := iVal;
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Deg2Rad : Degrees to radians (trig-boundary helper only; the
               application convention keeps all stored angles in degrees).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Deg2Rad : LREAL
VAR_INPUT
    (* Angle in degrees *)
    rDeg : LREAL;
END_VAR
    FUN_SP_Deg2Rad := rDeg * GC_DEG2RAD;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Rad2Deg : Radians to degrees (trig-boundary helper only; the
               application convention keeps all stored angles in degrees).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Rad2Deg : LREAL
VAR_INPUT
    (* Angle in radians *)
    rRad : LREAL;
END_VAR
    FUN_SP_Rad2Deg := rRad * GC_RAD2DEG;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Atan2 : Four-quadrant arctangent atan2(y, x), result in DEGREES,
               in (-180, 180]. Implemented with ATAN (radians) for full
               portability across targets; result mapped with GC_RAD2DEG.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Atan2 : LREAL
VAR_INPUT
    (* Y coordinate (ordinate) *)
    rY : LREAL;
    (* X coordinate (abscissa) *)
    rX : LREAL;
END_VAR
VAR
    (* Absolute value of rX *)
    rAbsX : LREAL;
    (* Absolute value of rY *)
    rAbsY : LREAL;
    (* Start value (t = 0) [rad] *)
    rA    : LREAL;
    (* Result being assembled per quadrant [rad] *)
    rRes  : LREAL;
END_VAR
    rAbsX := ABS(rX);
    rAbsY := ABS(rY);
    rA    := GC_REAL_MAX;

    (* Guard against both-zero case *)
    IF (rAbsX < 1.0E-12) AND (rAbsY < 1.0E-12) THEN
        FUN_SP_Atan2 := 0.0;
        RETURN;
    END_IF

    IF rAbsX > 1.0E-12 THEN
        rA := ATAN(rAbsY / rAbsX);
    END_IF

    IF rX > 0.0 THEN
        rRes := rA;
    ELSIF rX < 0.0 THEN
        IF rY >= 0.0 THEN
            rRes := GC_PI - rA;
        ELSE
            rRes := rA - GC_PI;
        END_IF
    ELSE (* rX = 0 *)
        IF rY > 0.0 THEN
            rRes := GC_PI / 2.0;
        ELSE
            rRes := -GC_PI / 2.0;
        END_IF
    END_IF

    FUN_SP_Atan2 := rRes * GC_RAD2DEG;  (* Radians -> application degrees *)
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_NormAng : Normalize an angle to (-180, 180] degrees.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_NormAng : LREAL
VAR_INPUT
    (* Angle to normalize [deg] *)
    rAng : LREAL;
END_VAR
VAR
    (* Working copy of the angle [deg] *)
    rA : LREAL;
END_VAR
    rA := rAng;
    WHILE rA >  GC_180 DO
        rA := rA - GC_360;
    END_WHILE
    WHILE rA <= -GC_180 DO
        rA := rA + GC_360;
    END_WHILE
    FUN_SP_NormAng := rA;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_AngDiff : Signed shortest angle from a to b [deg], in (-180, 180].
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_AngDiff : LREAL
VAR_INPUT
    (* Start angle a [deg] *)
    rFrom : LREAL;
    (* Target angle b [deg] *)
    rTo   : LREAL;
END_VAR
    FUN_SP_AngDiff := FUN_SP_NormAng(rTo - rFrom);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Dist2D : Euclidean distance between two 2D points.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Dist2D : LREAL
VAR_INPUT
    (* First point, X *)
    rX1 : LREAL;
    (* First point, Y *)
    rY1 : LREAL;
    (* Second point, X *)
    rX2 : LREAL;
    (* Second point, Y *)
    rY2 : LREAL;
END_VAR
    FUN_SP_Dist2D := SQRT((rX2 - rX1)*(rX2 - rX1) + (rY2 - rY1)*(rY2 - rY1));
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Lerp : Linear interpolation between two values.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Lerp : LREAL
VAR_INPUT
    (* Start value (t = 0) *)
    rA   : LREAL;
    (* End value (t = 1) *)
    rB   : LREAL;
    rT   : LREAL;   (* 0.0 .. 1.0 *)
END_VAR
    FUN_SP_Lerp := rA + (rB - rA) * FUN_SP_Clamp(rT, 0.0, 1.0);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_DigCh : Single character string for digit d (0..9).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_DigCh : STRING(1)
VAR_INPUT
    (* Digit value 0..9 *)
    iD : DINT;
END_VAR
    FUN_SP_DigCh := MID('0123456789', 1, FUN_SP_ClampI(iD + 1, 1, 10));
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_DigVal : Numeric value (0..9) of a single character, -1 if not a digit.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_DigVal : SINT
VAR_INPUT
    (* Character to classify as digit *)
    sCh : STRING(1);
END_VAR
VAR
    (* Position inside the digits table (0 = not a digit) *)
    iPos : INT;
    (* Digit loop index 0..9 *)
    i    : SINT;
    (* Digit character compared with sCh *)
    sD   : STRING(1);
END_VAR
    FUN_SP_DigVal := -1;
    iPos := FIND('0123456789', sCh);
    IF iPos > 0 THEN
        FOR i := 0 TO 9 DO
            sD := MID('0123456789', 1, SINT_TO_INT(i) + 1);
            IF sCh = sD THEN
                FUN_SP_DigVal := i;
                EXIT;
            END_IF
        END_FOR
    END_IF
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_ErrorText : Human readable text for a return code (English).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_ErrorText : STRING(40)
VAR_INPUT
    (* Return code to translate *)
    eRc : ET_SP_RetCode;
END_VAR
    CASE eRc OF
        ET_SP_RetCode#Done:        FUN_SP_ErrorText := 'OK';
        ET_SP_RetCode#Busy:        FUN_SP_ErrorText := 'Busy';
        ET_SP_RetCode#Idle:        FUN_SP_ErrorText := 'Idle';
        ET_SP_RetCode#ErrParam:    FUN_SP_ErrorText := 'Invalid parameter';
        ET_SP_RetCode#ErrState:    FUN_SP_ErrorText := 'Invalid state';
        ET_SP_RetCode#ErrFull:     FUN_SP_ErrorText := 'Buffer full';
        ET_SP_RetCode#ErrEmpty:    FUN_SP_ErrorText := 'Buffer empty';
        ET_SP_RetCode#ErrNotFound: FUN_SP_ErrorText := 'Not found';
        ET_SP_RetCode#ErrCom:      FUN_SP_ErrorText := 'Communication error';
        ET_SP_RetCode#ErrIo:       FUN_SP_ErrorText := 'I/O error';
        ET_SP_RetCode#ErrBusy:     FUN_SP_ErrorText := 'Resource busy';
        ET_SP_RetCode#ErrRange:    FUN_SP_ErrorText := 'Out of range';
        ELSE                       FUN_SP_ErrorText := 'Not implemented';
    END_CASE
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_SrcText : Short module tag for log/alarm prefixes (English).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_SrcText : STRING(12)
VAR_INPUT
    (* Module selector *)
    eSrc : ET_SP_LogSource;
END_VAR
    CASE eSrc OF
        ET_SP_LogSource#System:    FUN_SP_SrcText := 'SYSTEM';
        ET_SP_LogSource#Robot:     FUN_SP_SrcText := 'ROBOT';
        ET_SP_LogSource#Feed:      FUN_SP_SrcText := 'FEED';
        ET_SP_LogSource#Conveyor:  FUN_SP_SrcText := 'CONVEYOR';
        ET_SP_LogSource#Camera:    FUN_SP_SrcText := 'CAMERA';
        ET_SP_LogSource#Balancer:  FUN_SP_SrcText := 'BALANCER';
        ET_SP_LogSource#Batch:     FUN_SP_SrcText := 'BATCH';
        ET_SP_LogSource#Persist:   FUN_SP_SrcText := 'PERSIST';
        ET_SP_LogSource#Simulation:FUN_SP_SrcText := 'SIM';
        ELSE                       FUN_SP_SrcText := 'USER';
    END_CASE
END_FUNCTION
