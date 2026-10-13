(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 06_Pattern
   Worksheet : DUT - ST_SP_PatternTypes
   -----------------------------------------------------------------------------
   Purpose   : Placement pattern definitions (grid patterns with multi-tier
               tray support), batch definitions with type mix, and their
               runtime states.
   =============================================================================
*)

TYPE ST_SP_PattDef :
STRUCT
    bUsed    : BOOL;          (* Pattern slot in use *)
    sName    : STRING(24);    (* Human readable pattern name *)
    uiRows   : UINT;          (* Rows (along belt) *)
    uiCols   : UINT;          (* Columns (across belt) *)
    rDx      : LREAL;         (* Column pitch, across belt [mm] *)
    rDy      : LREAL;         (* Row pitch, along belt [mm] *)
    rRotStep : LREAL;         (* Rotation step per slot [deg], 0 = keep *)
    pBase    : ST_SP_Pose2D;  (* Base slot pose in FEED frame (u across, v upstream) *)
    uiLayers : UINT;          (* Number of tray layers (1 = single tier) *)
    rLayerH  : LREAL;         (* Layer height [mm] *)
    rZBase   : LREAL;         (* Z of layer 0 in world [mm] *)
    rTrigDist: LREAL;         (* Pattern repetition distance [mm] (Distance mode) *)
END_STRUCT
END_TYPE

TYPE ST_SP_BatchDef :
STRUCT
    bUsed     : BOOL;         (* Batch slot in use *)
    sName     : STRING(24);   (* Human readable batch name *)
    iOutFeed  : SINT;         (* Outfeed 1..GC_FEEDS *)
    uiPattId  : UINT;         (* Pattern index 1..GC_PATT *)
    aiMix     : ARRAY[1..8] OF UINT;   (* Type mix sequence 1..GC_SEQ (1..GC_TYPES) *)
    aiMixCnt  : ARRAY[1..8] OF UINT;   (* Slots per mix entry 1..GC_SEQ (per layer) *)
    udiQty    : UDINT;        (* Total target quantity *)
    eTrig     : ET_SP_PattTrig; (* Pattern instance trigger *)
    iPriority : SINT;         (* Scheduling priority (higher = sooner) *)
END_STRUCT
END_TYPE

TYPE ST_SP_BatchStat :
STRUCT
    eState   : ET_SP_BatchState;
    udiDone  : UDINT;         (* Targets placed *)
    udiGen   : UDINT;         (* Targets generated *)
    udiBatchId : UDINT;       (* Runtime batch id *)
    uiLayer  : UINT;          (* Current layer being generated *)
    udiTrays : UDINT;         (* Tray instances generated *)
END_STRUCT
END_TYPE

TYPE ST_SP_PattCmd :
STRUCT
    (* Pattern batch command mailbox (PRG_SP_TaskMain -> PRG_SP_TaskFast).
       The application task resolves the batch definition through the
       batch manager, then latches it here; the motion task consumes the
       request, runs StartBatch / AbortBatch on the pattern engine and
       clears the flags. iFeed is informational (7 or 8 in the base cell). *)
    bStart   : BOOL;          (* TRUE = pending StartBatch request *)
    bAbort   : BOOL;          (* TRUE = pending AbortBatch request *)
    iFeed    : SINT;          (* Outfeed the engine drives (1..GC_FEEDS) *)
    iBatch   : SINT;          (* Batch index (for diagnostics) *)
    stDef    : ST_SP_BatchDef;(* Resolved batch definition snapshot *)
    stPatt   : ST_SP_PattDef; (* Pattern definition snapshot (g_astPatt) *)
    udiBatchId : UDINT;       (* Runtime batch id for the engine *)
END_STRUCT
END_TYPE
