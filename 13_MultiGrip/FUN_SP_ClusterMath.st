(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 13_MultiGrip
   Worksheet : FUN - SP_ClusterMath
   -----------------------------------------------------------------------------
   Purpose   : Pure math shared by the multi-grip cluster machinery:

     FUN_SP_FitYaw          : circular mean of the member item yaws ->
                              synchronized TCP yaw.
     FUN_SP_ClusterResidual : maximum per-cup position residual of a
                              candidate TCP pose against the member items
                              (least-squares fit quality metric).

   TCP pose model:
     cup world position = TCP + Rot(yaw) * cup_offset(tool frame)
   The synchronized descent is correct when every cup lands on its own
   item; the residual function measures the worst violation.

   Constraints: pure functions, no globals written, no pointers,
   VAR_INPUT only (codebase convention: functions have no VAR_IN_OUT).
   =============================================================================
*)

(* -----------------------------------------------------------------------
   FUNCTION: FUN_SP_FitYaw
   Circular mean of the first uiN item yaws (rTh): atan2(mean sin, mean cos).
   Angles are stored in DEGREES; the sin/cos evaluation converts deg -> rad
   at the trig boundary. Robust to the +/- 180 deg wrap for parts anywhere
   around the belt; result in (-180, 180] degrees.
   ----------------------------------------------------------------------- *)
FUNCTION FUN_SP_FitYaw : LREAL
VAR_INPUT
    (* Member item poses (world) 1..GC_CUPS *)
    astP : ARRAY[1..4] OF ST_SP_Pose3D;
    (* Number of valid members 1..GC_CUPS *)
    uiN  : UINT;
END_VAR
VAR
    (* Member loop index (yaw accumulation) *)
    i  : SINT;
    (* Sine / cosine accumulators of the unit vectors *)
    rS, rC : LREAL;
END_VAR
    rS := 0.0;
    rC := 0.0;
    IF uiN < UINT#1 THEN
        FUN_SP_FitYaw := 0.0;
        RETURN;
    END_IF
    FOR i := 1 TO UINT_TO_SINT(uiN) DO
        rS := rS + SIN(astP[i].rTh * GC_DEG2RAD);
        rC := rC + COS(astP[i].rTh * GC_DEG2RAD);
    END_FOR
    FUN_SP_FitYaw := FUN_SP_Atan2(rS, rC);   (* [deg] *)
END_FUNCTION


(* -----------------------------------------------------------------------
   FUNCTION: FUN_SP_ClusterResidual
   Worst-case (maximum) cup-to-item distance for a candidate TCP pose:
     res_k = | TCP.xy + Rot(yaw)*cup_k.xy - item_k.xy |
   Used by the planner to accept/drop cluster members and by the robot
   to validate a synchronized place formation.
   ----------------------------------------------------------------------- *)
FUNCTION FUN_SP_ClusterResidual : LREAL
VAR_INPUT
    (* Member item poses (world, XY used) 1..GC_CUPS *)
    astP  : ARRAY[1..4] OF ST_SP_Pose3D;
    (* Cup offsets in the tool frame (XY used) 1..GC_CUPS *)
    astC  : ARRAY[1..4] OF ST_SP_Point3D;
    (* Candidate synchronized TCP pose *)
    stTcp : ST_SP_Pose3D;
    (* Number of valid members/cups 1..GC_CUPS *)
    uiN   : UINT;
END_VAR
VAR
    (* Member loop index (residual scan) *)
    i  : SINT;
    (* Cup position rotated into the world frame *)
    rCx, rCy : LREAL;
    (* Per-member residual [mm] *)
    rD : LREAL;
END_VAR
    FUN_SP_ClusterResidual := 0.0;
    IF uiN < UINT#1 THEN
        RETURN;
    END_IF
    FOR i := 1 TO UINT_TO_SINT(uiN) DO
        rCx := FUN_SP_RotX(stTcp.rTh, astC[i].rX, astC[i].rY);
        rCy := FUN_SP_RotY(stTcp.rTh, astC[i].rX, astC[i].rY);
        rD  := SQRT( (stTcp.rX + rCx - astP[i].rX) * (stTcp.rX + rCx - astP[i].rX)
                   + (stTcp.rY + rCy - astP[i].rY) * (stTcp.rY + rCy - astP[i].rY) );
        IF rD > FUN_SP_ClusterResidual THEN
            FUN_SP_ClusterResidual := rD;
        END_IF
    END_FOR
END_FUNCTION
