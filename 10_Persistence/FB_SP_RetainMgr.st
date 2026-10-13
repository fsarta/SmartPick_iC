(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 10_Persistence
   Worksheet : FB - SP_RetainMgr
   -----------------------------------------------------------------------------
   Purpose   : Retain lifecycle manager (power-failure continuity):
               - First cycle: validate the retained blob checksum; on
                 mismatch restore defaults and flag for the HMI.
               - Cyclic: keep the checksum fresh (retain memory holds the
                 payload; declared in GVL_SP_Prod.g_stRetain as VAR RETAIN).
               - SaveNow(): explicit flush point for the application.

   Restored content: lifetime counters, last recipe name, camera control
   ownership, batch progress -> "system handles robot power failure"
   (MotoPick 4 resiliency parity at data level).
   =============================================================================
*)

FUNCTION_BLOCK SP_RetainMgr
(* ----------------------------- Interface ------------------------------- *)
VAR_OUTPUT
    bRestored : BOOL;           (* TRUE = valid retain data available *)
    bDefaults : BOOL;           (* TRUE = blob was invalid, defaults applied *)
    uiVer     : UINT;
END_VAR
VAR
    (* TRUE on the first cycle (retain validity decision) *)
    m_bFirst : BOOL := TRUE;
END_VAR

(* ------------------------------- Body ---------------------------------- *)
IF m_bFirst THEN
    m_bFirst := FALSE;
    IF THIS.Validate() THEN
        bRestored := TRUE;
        bDefaults := FALSE;
    ELSE
        THIS.RestoreDefaults();
        bRestored := FALSE;
        bDefaults := TRUE;
    END_IF
END_IF

(* Keep header fresh (checksum covers the payload fields) *)
g_stRetain.uiVer := UINT#1;
g_stRetain.uiSum := THIS.ChkSum();
uiVer := g_stRetain.uiVer;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: Validate (parent SP_RetainMgr) - internal
   TRUE when the blob was initialized and the checksum matches.
   ----------------------------------------------------------------------- *)
METHOD Validate : BOOL
    Validate := g_stRetain.bInit AND (g_stRetain.uiSum = THIS.ChkSum());
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: RestoreDefaults (parent SP_RetainMgr) - internal
   ----------------------------------------------------------------------- *)
METHOD RestoreDefaults : BOOL
VAR
    (* Robot loop index (restore/copy) *)
    i : SINT;
END_VAR
    RestoreDefaults := TRUE;        (* Defaults restored *)
    g_stRetain.uiVer := UINT#1;
    g_stRetain.bInit := TRUE;
    g_stRetain.sRecipe := '';
    g_stRetain.udiPickTotal := UDINT#0;
    g_stRetain.udiPlaceTotal := UDINT#0;
    FOR i := 1 TO GC_CAMS DO
        g_stRetain.aiCamOwner[i] := GC_ID_NONE;
    END_FOR
    FOR i := 1 TO GC_BATCHES DO
        g_stRetain.astBatch[i].eState := ET_SP_BatchState#Idle;
        g_stRetain.astBatch[i].udiDone := UDINT#0;
        g_stRetain.astBatch[i].udiGen := UDINT#0;
        g_stRetain.astBatch[i].udiTrays := UDINT#0;
        g_stRetain.astBatch[i].uiLayer := UINT#0;
        g_stRetain.astBatch[i].udiBatchId := UDINT#0;
    END_FOR
    g_stRetain.uiSum := THIS.ChkSum();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: ChkSum (parent SP_RetainMgr) - internal
   Additive checksum over the payload fields (portability substitute of
   a CRC; not cryptographic by design).
   ----------------------------------------------------------------------- *)
METHOD ChkSum : UDINT
VAR
    (* Feed loop index (restore/copy) *)
    i : SINT;
    (* Checksum of the retain payload (validation) *)
    udi : UDINT;
END_VAR
    udi := FUN_SP_StrSum(g_stRetain.sRecipe);
    udi := udi + g_stRetain.udiPickTotal + g_stRetain.udiPlaceTotal * UDINT#3;
    FOR i := 1 TO GC_CAMS DO
        udi := udi + SINT_TO_UDINT(g_stRetain.aiCamOwner[i]) * UDINT#7;
    END_FOR
    FOR i := 1 TO GC_BATCHES DO
        udi := udi + g_stRetain.astBatch[i].udiDone * UDINT#11
                    + g_stRetain.astBatch[i].udiTrays * UDINT#13;
    END_FOR
    ChkSum := udi;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SaveNow (parent SP_RetainMgr)
   Explicit flush: refresh counters from the application and recompute
   the checksum (retain write happens by the runtime on change).
   ----------------------------------------------------------------------- *)
METHOD SaveNow : BOOL
    SaveNow := TRUE;                (* Snapshot refreshed *)
    g_stRetain.uiVer := UINT#1;
    g_stRetain.uiSum := THIS.ChkSum();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: SetRecipe (parent SP_RetainMgr)
   Remember the last loaded recipe (power-failure continuity).
   ----------------------------------------------------------------------- *)
METHOD SetRecipe : BOOL
VAR_INPUT
    (* Retain mirror file name *)
    sName : STRING(32);
END_VAR
    SetRecipe := (LEN(sName) > 0);  (* TRUE = name accepted *)
    IF LEN(sName) > 0 THEN
        g_stRetain.sRecipe := sName;
    END_IF
END_METHOD
