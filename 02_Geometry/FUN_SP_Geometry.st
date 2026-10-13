(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 02_Geometry
   Worksheet : FUNCTION(s) - FUN_SP_Geometry
   -----------------------------------------------------------------------------
   Purpose   : Frame transformation helpers. Each function returns one
               scalar component so that poses flow through pure functions
               (no VAR_IN_OUT, no struct return dependency).
               If the tool requires one FUNCTION per worksheet, split each
               FUNCTION block into its own worksheet keeping exact names.
   =============================================================================
*)


(* -----------------------------------------------------------------------------
   FUN_SP_TrfX : X component of applying transform T to point (rX, rY).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_TrfX : LREAL
VAR_INPUT
    (* Transform to apply *)
    stT : ST_SP_Transf2D;
    (* Point X to rotate *)
    rX  : LREAL;
    (* Point Y to rotate *)
    rY  : LREAL;
END_VAR
    FUN_SP_TrfX := stT.rDx + stT.rScale * ( COS(stT.rRot * GC_DEG2RAD)*rX
                                            - SIN(stT.rRot * GC_DEG2RAD)*rY );
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_TrfY : Y component of applying transform T to point (rX, rY).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_TrfY : LREAL
VAR_INPUT
    (* Transform to apply *)
    stT : ST_SP_Transf2D;
    (* Point X to rotate *)
    rX  : LREAL;
    (* Point Y to rotate *)
    rY  : LREAL;
END_VAR
    FUN_SP_TrfY := stT.rDy + stT.rScale * ( SIN(stT.rRot * GC_DEG2RAD)*rX
                                            + COS(stT.rRot * GC_DEG2RAD)*rY );
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_TrfTh : Rotation component of applying transform T to angle rTh.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_TrfTh : LREAL
VAR_INPUT
    (* Transform to apply *)
    stT : ST_SP_Transf2D;
    (* Angle to transform [deg] *)
    rTh : LREAL;
END_VAR
    FUN_SP_TrfTh := FUN_SP_NormAng(stT.rRot + rTh);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_InvTrfX : X component of applying the inverse of T to point.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_InvTrfX : LREAL
VAR_INPUT
    (* Transform whose inverse is applied *)
    stT : ST_SP_Transf2D;
    (* Point X to rotate *)
    rX  : LREAL;
    (* Point Y to rotate *)
    rY  : LREAL;
END_VAR
VAR
    (* Point relative to translation (X - rDx) *)
    rPx : LREAL;
    (* Point relative to translation (Y - rDy) *)
    rPy : LREAL;
    (* Scale of the transform (degeneracy guard) *)
    rS  : LREAL;
END_VAR
    rPx := rX - stT.rDx;
    rPy := rY - stT.rDy;
    rS  := stT.rScale;
    IF ABS(rS) < 1.0E-9 THEN
        FUN_SP_InvTrfX := 0.0;      (* Degenerate transform guard *)
        RETURN;
    END_IF
    (* R(rot)^-1 = R(-rot); rot in deg -> rad at the trig boundary *)
    FUN_SP_InvTrfX := ( COS(stT.rRot * GC_DEG2RAD)*rPx
                      + SIN(stT.rRot * GC_DEG2RAD)*rPy ) / rS;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_InvTrfY : Y component of applying the inverse of T to point.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_InvTrfY : LREAL
VAR_INPUT
    (* Transform whose inverse is applied *)
    stT : ST_SP_Transf2D;
    (* Point X to rotate *)
    rX  : LREAL;
    (* Point Y to rotate *)
    rY  : LREAL;
END_VAR
VAR
    (* Point relative to translation (X - rDx) *)
    rPx : LREAL;
    (* Point relative to translation (Y - rDy) *)
    rPy : LREAL;
    (* Scale of the transform (degeneracy guard) *)
    rS  : LREAL;
END_VAR
    rPx := rX - stT.rDx;
    rPy := rY - stT.rDy;
    rS  := stT.rScale;
    IF ABS(rS) < 1.0E-9 THEN
        FUN_SP_InvTrfY := 0.0;      (* Degenerate transform guard *)
        RETURN;
    END_IF
    FUN_SP_InvTrfY := ( -SIN(stT.rRot * GC_DEG2RAD)*rPx
                      + COS(stT.rRot * GC_DEG2RAD)*rPy ) / rS;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_InvTrfTh : Angle component of applying the inverse of T.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_InvTrfTh : LREAL
VAR_INPUT
    (* Transform whose inverse is applied *)
    stT : ST_SP_Transf2D;
    (* Angle to transform [deg] *)
    rTh : LREAL;
END_VAR
    FUN_SP_InvTrfTh := FUN_SP_NormAng(rTh - stT.rRot);
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_RotX : X component of rotating (rX, rY) by rAng about origin.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_RotX : LREAL
VAR_INPUT
    (* Rotation angle about origin [deg] *)
    rAng : LREAL;
    (* Point X to rotate *)
    rX   : LREAL;
    (* Point Y to rotate *)
    rY   : LREAL;
END_VAR
    FUN_SP_RotX := COS(rAng * GC_DEG2RAD)*rX - SIN(rAng * GC_DEG2RAD)*rY;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_RotY : Y component of rotating (rX, rY) by rAng about origin.
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_RotY : LREAL
VAR_INPUT
    (* Rotation angle about origin [deg] *)
    rAng : LREAL;
    (* Point X to rotate *)
    rX   : LREAL;
    (* Point Y to rotate *)
    rY   : LREAL;
END_VAR
    FUN_SP_RotY := SIN(rAng * GC_DEG2RAD)*rX + COS(rAng * GC_DEG2RAD)*rY;
END_FUNCTION


(* -----------------------------------------------------------------------------
   FUN_SP_Pose3InWin : TRUE when pose p3 is inside an axis-aligned XY window
               (used for work-range and region checks).
   ----------------------------------------------------------------------------- *)
FUNCTION FUN_SP_Pose3InWin : BOOL
VAR_INPUT
    (* Pose to test (X/Y used, Z ignored) *)
    p3     : ST_SP_Pose3D;
    (* Window lower X bound *)
    rXmin  : LREAL;
    (* Window upper X bound *)
    rXmax  : LREAL;
    (* Window lower Y bound *)
    rYmin  : LREAL;
    (* Window upper Y bound *)
    rYmax  : LREAL;
END_VAR
    FUN_SP_Pose3InWin := (p3.rX >= rXmin) AND (p3.rX <= rXmax)
                     AND (p3.rY >= rYmin) AND (p3.rY <= rYmax);
END_FUNCTION
