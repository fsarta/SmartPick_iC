(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FB - SP_MovAvg
   -----------------------------------------------------------------------------
   Purpose   : Finite impulse response moving average filter for LREAL
               signals (conveyor speed, analog measures).
   -----------------------------------------------------------------------------
   Behavior  : Call once per task cycle. The output follows the arithmetic
               mean of the last nSamples valid samples.
   =============================================================================
*)

FUNCTION_BLOCK SP_MovAvg
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    rIn      : LREAL;         (* Raw input sample *)
    bEnable  : BOOL;          (* TRUE = filter active, FALSE = bypass/reset *)
END_VAR
VAR_OUTPUT
    rOut     : LREAL;         (* Filtered output *)
    bFilled  : BOOL;          (* TRUE once the window is completely filled *)
END_VAR
VAR
    m_arBuf  : ARRAY[1..16] OF LREAL; (* Sample window 1..GC_MOVAVG_N *)
    m_iHead  : SINT  := 1;   (* Next write index (1-based) *)
    m_iCnt   : SINT  := 0;   (* Valid sample count *)
    m_rSum   : LREAL := 0.0; (* Running sum for O(1) evaluation *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF NOT bEnable THEN
    (* Reset the filter state and pass the input through unfiltered *)
    m_iHead := 1;
    m_iCnt  := 0;
    m_rSum  := 0.0;
    rOut    := rIn;
    bFilled := FALSE;
    RETURN;
END_IF

(* Overwrite oldest sample with the newest one (ring buffer) *)
IF m_iCnt < GC_MOVAVG_N THEN
    m_rSum := m_rSum + rIn;
    m_iCnt := m_iCnt + 1;
ELSE
    m_rSum := m_rSum - m_arBuf[m_iHead] + rIn;
END_IF
m_arBuf[m_iHead] := rIn;

m_iHead := m_iHead + 1;
IF m_iHead > GC_MOVAVG_N THEN
    m_iHead := 1;
END_IF

rOut    := m_rSum / UDINT_TO_LREAL(SINT_TO_UDINT(m_iCnt));
bFilled := (m_iCnt >= GC_MOVAVG_N);
END_FUNCTION_BLOCK 
