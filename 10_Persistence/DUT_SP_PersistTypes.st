(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 10_Persistence
   Worksheet : DUT - ST_SP_PersistTypes
   -----------------------------------------------------------------------------
   Purpose   : Persistence data model: retain blob (restored after power
               failure: calibration, counters, batch progress, camera
               ownership) and recipe header.
   =============================================================================
*)

TYPE ST_SP_RetainData :
STRUCT
    (* Header *)
    uiVer    : UINT;            (* Blob layout version *)
    uiSum    : UDINT;           (* Additive checksum of the payload *)
    bInit    : BOOL;            (* TRUE after first valid restore *)
    (* Continuity *)
    sRecipe  : STRING(32);      (* Last loaded recipe name *)
    udiPickTotal : UDINT;       (* Lifetime picks *)
    udiPlaceTotal: UDINT;       (* Lifetime placements *)
    (* Camera control ownership (resiliency) 1..GC_CAMS *)
    aiCamOwner : ARRAY[1..2] OF SINT;
    (* Batch progress per definition 1..GC_BATCHES *)
    astBatch : ARRAY[1..8] OF ST_SP_BatchStat;
END_STRUCT
END_TYPE

TYPE ST_SP_RecipeHdr :
STRUCT
    sName : STRING(32);         (* Recipe name (file name stem) *)
    uiVer : UINT;               (* Format version *)
    uiSum : UDINT;              (* Content checksum (informational) *)
END_STRUCT
END_TYPE
