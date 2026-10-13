(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 11_Simulation
   Worksheet : FB - SP_SimCamera
   -----------------------------------------------------------------------------
   Purpose   : Virtual camera for offline tests: on trigger (distance
               policy or external call) generates a batch of items with
               pseudo-random poses along the belt and injects them into a
               SP_VisionCam through InjectItem (the same path used by the
               real drivers' output, so the full downstream logic is
               exercised: frame transforms, queues, load sharing, robots).

   Random generator: 32-bit LCG (deterministic per seed - reproducible
   test scenarios).
   =============================================================================
*)

FUNCTION_BLOCK SP_SimCamera
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    out_stItem : ST_SP_VisionItem;  (* Drained item (GetNextItem) *)
    stVi       : ST_SP_VisionItem;  (* Last generated item *)
END_VAR
VAR_INPUT
    bEnable : BOOL;             (* Scenario active *)
    iCam    : SINT;             (* Target camera index 1..GC_CAMS *)
    iFeed   : SINT;             (* Target feed index 1..GC_FEEDS *)
    rEncNow : LREAL;            (* Belt encoder [mm] *)
    rTrigDist : LREAL := 200.0; (* Spawn distance [mm] *)
    uiItemsPerImg : UINT := 3;  (* Items per image (1..GC_VIS_MAX) *)
    uiTypeMin : UINT := 1;      (* Type mix lower bound *)
    uiTypeMax : UINT := 4;      (* Type mix upper bound *)
    rXmin : LREAL := -80.0;     (* Across-belt span [mm] *)
    rXmax : LREAL := 80.0;
    rVmin : LREAL := 60.0;      (* Upstream offset span [mm] *)
    rVmax : LREAL := 300.0;
    rBeltZ : LREAL := 0.0;      (* Belt surface Z (world) *)
    uiDtMs : UDINT;
    bTrigExt : BOOL;            (* External spawn request (edge) *)
END_VAR
VAR
    (* LCG random seed (deterministic simulation) *)
    m_udiSeed : UDINT := UDINT#123456789;
    (* Belt position at the last simulated trigger [mm] *)
    m_rLastTrig : LREAL := -1.0E9;
    (* Previous external trigger (edge detection) *)
    m_bExtPrev : BOOL;
    (* Simulated item id generator *)
    m_udiId : UDINT := UDINT#0;
    (* Out-queue drained by the wiring program -> VisionCam.InjectItem 1..GC_VIS_MAX2 *)
    m_astQ  : ARRAY[1..32] OF ST_SP_VisionItem;
    (* Simulated items waiting for injection *)
    m_iQCnt : SINT := 0;
    (* Injection read index *)
    m_iQRd  : SINT := 0;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF NOT bEnable THEN
    m_rLastTrig := -1.0E9;
    RETURN;
END_IF

(* Distance policy + external edge *)
IF (ABS(rEncNow - m_rLastTrig) >= rTrigDist) OR (bTrigExt AND NOT m_bExtPrev) THEN
    m_rLastTrig := rEncNow;
    THIS.SpawnBatch();
END_IF
m_bExtPrev := bTrigExt;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: SpawnBatch (parent SP_SimCamera) - internal
   Generate one image worth of items into the out-queue. The wiring
   program drains it via GetNextItem and calls VisionCam.InjectItem.
   ----------------------------------------------------------------------- *)
METHOD SpawnBatch : UINT
VAR
    (* Spawn loop index *)
    i : DINT;
    (* Items to spawn for this trigger *)
    uiN : UINT;
    (* Simulated item under construction *)
    stIt : ST_SP_VisionItem;
    (* Random X / speed-scaled offset / yaw of the item [deg] *)
    rX, rV, rTh : LREAL;
    (* Random product type id *)
    uiType : UINT;
    (* Items actually queued by this call *)
    uiQ : UINT := UINT#0;
END_VAR
    SpawnBatch := UINT#0;
    IF m_iQRd >= m_iQCnt THEN
        m_iQCnt := 0;
        m_iQRd  := 0;
    END_IF
    uiN := DINT_TO_UINT(FUN_SP_ClampI(UINT_TO_DINT(uiItemsPerImg), 1, SINT_TO_DINT(GC_VIS_MAX)));

    FOR i := 1 TO UINT_TO_DINT(uiN) DO
        rX := rXmin + (rXmax - rXmin) * THIS.Rand();
        rV := rVmin + (rVmax - rVmin) * THIS.Rand();
        rTh := (THIS.Rand() - 0.5) * GC_90;   (* Uniform yaw in +/-45 deg *)
        uiType := uiTypeMin
                  + DINT_TO_UINT(TRUNC((UDINT_TO_LREAL(UINT_TO_UDINT(uiTypeMax - uiTypeMin)) + 1.0) * THIS.Rand()));
        IF uiType > uiTypeMax THEN
            uiType := uiTypeMax;
        END_IF
        IF uiType < UINT#1 THEN
            uiType := UINT#1;
        END_IF

        m_udiId := m_udiId + UDINT#1;
        stIt.udiId := UDINT#0;              (* Reassigned by the camera *)
        stIt.uiTypeId := uiType;
        (* Simulated camera frame = feed frame (identity calibration) *)
        stIt.p2.rX := rX;
        stIt.p2.rY := rV;
        stIt.p2.rTh := rTh;
        stIt.rScore := 0.95;
        stIt.rWeight := 0.0;
        stIt.rBeltPos := rEncNow;
        stIt.bTarget := FALSE;
        stIt.bValid := TRUE;

        IF m_iQCnt < GC_VIS_MAX2 THEN
            m_iQCnt := m_iQCnt + 1;
            m_astQ[m_iQCnt] := stIt;
            uiQ := uiQ + UINT#1;
        END_IF
        stVi := stIt;
    END_FOR
    SpawnBatch := uiQ;              (* Items queued this call *)
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetNextItem (parent SP_SimCamera)
   Drain one generated item into out_stItem. TRUE while available.
   ----------------------------------------------------------------------- *)
METHOD GetNextItem : BOOL
    GetNextItem := FALSE;
    IF m_iQRd < m_iQCnt THEN
        m_iQRd := m_iQRd + 1;
        out_stItem := m_astQ[m_iQRd];
        GetNextItem := TRUE;
    ELSE
        m_iQCnt := 0;
        m_iQRd := 0;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Rand (parent SP_SimCamera) - internal
   Uniform [0,1) from a 32-bit LCG (deterministic, reproducible).
   ----------------------------------------------------------------------- *)
METHOD Rand : LREAL
    m_udiSeed := m_udiSeed * UDINT#1103515245 + UDINT#12345;
    Rand := UDINT_TO_LREAL(m_udiSeed MOD UDINT#1000000) / 1000000.0;
END_METHOD
