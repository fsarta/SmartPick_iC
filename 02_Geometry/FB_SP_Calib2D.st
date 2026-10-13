(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 02_Geometry
   Worksheet : FB - SP_Calib2D
   -----------------------------------------------------------------------------
   Purpose   : Camera/conveyor frame calibration by point-pair acquisition.
               Solates a similarity transform (rotation + uniform scale +
               translation) mapping camera pixel-derived coordinates into
               the feed/world frame.

               Procedure (2 points minimum):
                 1. Move a reference part (or teaching target) to a known
                    world position P1; acquire its camera coordinate C1.
                    THIS.AddPair(C1, P1).
                 2. Repeat for P2 (well separated from P1, ideally across
                    the full field of view for best angle/scale estimate).
                 3. THIS.Compute().
               With more than 2 points the transform is the average of all
               pairwise solutions (robust against single-point outliers);
               residuals are reported as RMS.

               The result (out_stT) also compensates conveyor misalignment
               against the camera axis (feature parity with MotoPick 4).
   -----------------------------------------------------------------------------
   Methods   : Reset            - drop all pairs
               AddPair          - register one camera/world point pair
               Compute          - solve transform, set out_* results
   =============================================================================
*)

FUNCTION_BLOCK SP_Calib2D
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    out_stT    : ST_SP_Transf2D;    (* Solved transform (bValid set) *)
    out_rRms   : LREAL;             (* RMS residual [user unit] *)
    out_iPairs : SINT;              (* Registered pairs *)
    out_bValid : BOOL;              (* Transform usable *)
END_VAR
VAR
    m_acstCam : ARRAY[1..8] OF ST_SP_Point2D;  (* Camera points 1..GC_CALIB_PTS *)
    m_acstWrld: ARRAY[1..8] OF ST_SP_Point2D;  (* World points 1..GC_CALIB_PTS *)
    m_iCnt    : SINT := 0;          (* Stored pairs *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Passive FB: acquisition and solving driven by methods. *)
out_iPairs := m_iCnt;
out_bValid := out_stT.bValid;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Reset (parent SP_Calib2D)
   Drop all registered pairs and invalidate the transform.
   ----------------------------------------------------------------------- *)
METHOD Reset : BOOL
    Reset := TRUE;                  (* Pairs dropped *)
    m_iCnt := 0;
    out_stT.bValid := FALSE;
    out_bValid := FALSE;
    out_rRms := 0.0;
    out_iPairs := 0;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AddPair (parent SP_Calib2D)
   Register one point pair: camera coordinate (rCx, rCy) with the
   corresponding world coordinate (rWx, rWy).
   Returns Done, or ErrFull when MAXPTS reached.
   ----------------------------------------------------------------------- *)
METHOD AddPair : ET_SP_RetCode
VAR_INPUT
    (* Camera-frame X of the teaching point *)
    rCx : LREAL;
    (* Camera-frame Y of the teaching point *)
    rCy : LREAL;
    (* World-frame X of the same physical point *)
    rWx : LREAL;
    (* World-frame Y of the same physical point *)
    rWy : LREAL;
END_VAR
    AddPair := ET_SP_RetCode#Done;
    IF m_iCnt >= GC_CALIB_PTS THEN
        AddPair := ET_SP_RetCode#ErrFull;
        RETURN;
    END_IF
    m_iCnt := m_iCnt + 1;
    m_acstCam[m_iCnt].rX := rCx;
    m_acstCam[m_iCnt].rY := rCy;
    m_acstWrld[m_iCnt].rX := rWx;
    m_acstWrld[m_iCnt].rY := rWy;
    out_iPairs := m_iCnt;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Compute (parent SP_Calib2D)
   Solve the similarity transform from the registered pairs.
   - 2 pairs : exact solution (rotation, scale, translation).
   - >2 pairs: average of all pairwise exact solutions + RMS residual.
   Returns Done / ErrParam (insufficient or degenerate points).
   ----------------------------------------------------------------------- *)
METHOD Compute : ET_SP_RetCode
VAR
    (* Pairwise-solution loop indices (iK reuses pairs for RMS) *)
    i, j, iK  : SINT;
    (* Camera vector between the two points of the pair *)
    rDCx, rDCy: LREAL;
    (* World vector between the two points of the pair *)
    rDWx, rDWy: LREAL;
    (* Rotation and uniform scale of the pairwise solution [deg] *)
    rRot, rSc : LREAL;
    (* Vector lengths used for degeneracy check and scale *)
    rLenC, rLenW : LREAL;
    (* Translation of the pairwise solution *)
    rTx, rTy  : LREAL;
    (* Accumulators averaged over all valid pairs *)
    rSumRot, rSumSc, rSumTx, rSumTy : LREAL;
    (* Point residual and squared-residual accumulator (RMS) *)
    rRes, rSumRes : LREAL;
    (* Number of non-degenerate pairwise solutions *)
    iSols     : SINT;
    (* Averaged transform before validation *)
    stSol     : ST_SP_Transf2D;
    (* Camera point mapped through stSol (residual check) *)
    rXt, rYt  : LREAL;
END_VAR
    Compute := ET_SP_RetCode#ErrParam;

    IF m_iCnt < 2 THEN
        RETURN;               (* Need at least two points *)
    END_IF

    rSumRot := 0.0; rSumSc := 0.0; rSumTx := 0.0; rSumTy := 0.0;
    iSols   := 0;

    FOR i := 1 TO (m_iCnt - 1) DO
        FOR j := (i + 1) TO m_iCnt DO
            (* Vector pair between the two points *)
            rDCx := m_acstCam[j].rX - m_acstCam[i].rX;
            rDCy := m_acstCam[j].rY - m_acstCam[i].rY;
            rDWx := m_acstWrld[j].rX - m_acstWrld[i].rX;
            rDWy := m_acstWrld[j].rY - m_acstWrld[i].rY;

            rLenC := SQRT(rDCx*rDCx + rDCy*rDCy);
            rLenW := SQRT(rDWx*rDWx + rDWy*rDWy);

            (* Skip degenerate pairs by scoping the solution inside IF
               (structured text portability: no CONTINUE statement) *)
            IF (rLenC >= GC_DIST_EPS) AND (rLenW >= GC_DIST_EPS) THEN
                (* Rotation (deg) and scale from the vector pair; FUN_SP_Atan2
                   returns degrees, normalized so pairwise results average
                   without wrap-around artifacts *)
                rRot := FUN_SP_NormAng(FUN_SP_Atan2(rDWy, rDWx)
                                     - FUN_SP_Atan2(rDCy, rDCx));
                rSc  := rLenW / rLenC;

                (* Translation: map first point of the pair onto its world twin
                   (rot deg -> rad at the trig boundary) *)
                rTx := m_acstWrld[i].rX
                       - ( COS(rRot * GC_DEG2RAD)*m_acstCam[i].rX
                         - SIN(rRot * GC_DEG2RAD)*m_acstCam[i].rY ) * rSc;
                rTy := m_acstWrld[i].rY
                       - ( SIN(rRot * GC_DEG2RAD)*m_acstCam[i].rX
                         + COS(rRot * GC_DEG2RAD)*m_acstCam[i].rY ) * rSc;

                rSumRot := rSumRot + rRot;
                rSumSc  := rSumSc  + rSc;
                rSumTx  := rSumTx  + rTx;
                rSumTy  := rSumTy  + rTy;
                iSols   := iSols + 1;
            END_IF
        END_FOR
    END_FOR

    IF iSols = 0 THEN
        RETURN;                   (* All pairs degenerate *)
    END_IF

    stSol.rRot   := rSumRot / UDINT_TO_LREAL(SINT_TO_UDINT(iSols));
    stSol.rScale := rSumSc  / UDINT_TO_LREAL(SINT_TO_UDINT(iSols));
    stSol.rDx    := rSumTx  / UDINT_TO_LREAL(SINT_TO_UDINT(iSols));
    stSol.rDy    := rSumTy  / UDINT_TO_LREAL(SINT_TO_UDINT(iSols));
    stSol.bValid := TRUE;

    IF ABS(stSol.rScale) < 1.0E-6 THEN
        stSol.bValid := FALSE;
        out_stT := stSol;
        Compute := ET_SP_RetCode#ErrRange;
        RETURN;
    END_IF

    (* RMS residual over all registered points *)
    rSumRes := 0.0;
    FOR iK := 1 TO m_iCnt DO
        rXt := FUN_SP_TrfX(stSol, m_acstCam[iK].rX, m_acstCam[iK].rY);
        rYt := FUN_SP_TrfY(stSol, m_acstCam[iK].rX, m_acstCam[iK].rY);
        rRes := FUN_SP_Dist2D(rXt, rYt, m_acstWrld[iK].rX, m_acstWrld[iK].rY);
        rSumRes := rSumRes + rRes * rRes;
    END_FOR
    out_rRms := SQRT(rSumRes / UDINT_TO_LREAL(SINT_TO_UDINT(m_iCnt)));

    out_stT := stSol;
    out_bValid := TRUE;
    Compute := ET_SP_RetCode#Done;
END_METHOD
