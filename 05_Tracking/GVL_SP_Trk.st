(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 05_Tracking
   Worksheet : GVL - GVL_SP_Trk
   -----------------------------------------------------------------------------
   Purpose   : Tracking module constants.
   =============================================================================
*)

VAR CONSTANT
    GC_WIN_BEHIND : LREAL := 20.0;  (* Belt offset behind pick line before an
                                       unreserved item is declared Lost [mm] *)
END_VAR
