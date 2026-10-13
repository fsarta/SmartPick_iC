(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 05_Tracking
   Worksheet : DUT - ST_SP_TrkTypes
   -----------------------------------------------------------------------------
   Purpose   : Tracked item model, reservation request/response and feed
               (tracked conveyor) configuration.

   Frame model:
     - The feed owns a conveyor->world similarity transform (ST_SP_Transf2D)
       and a per-camera calibration (camera->feed frame).
     - An item is stored with its belt coordinate (distance upstream of the
       pick line) at capture time; its live belt offset is reconstructed
       from the encoder delta since capture.
     - At reservation the world pose is predicted on the pick line using
       current belt speed (cut-off reservation), maximizing window usage.
   =============================================================================
*)

TYPE ST_SP_TrkItem :
STRUCT
    udiId     : UDINT;          (* Globally unique id (from camera) *)
    uiTypeId  : UINT;           (* Product type 1..GC_TYPES *)
    rBeltCap  : LREAL;          (* Belt offset at capture, upstream of pick line [mm] *)
    rEncCap   : LREAL;          (* Belt encoder coordinate at capture [mm] *)
    p2World   : ST_SP_Pose2D;   (* World pose at capture (feed frame) *)
    rWeight   : REAL;           (* Part weight [g], 0 = unknown *)
    rScore    : REAL;           (* Vision score [0..1] *)
    eState    : ET_SP_ItemState;
    iReservedBy : SINT;         (* Robot id holding the reservation (0 = none) *)
    uiAttempts: UINT;           (* Pick attempts (retry policy) *)
    bTarget   : BOOL;           (* TRUE = placement target (pattern slot) *)
    udiBatchId: UDINT;          (* Owning batch for targets *)
    uiSlot    : UINT;           (* Pattern slot for targets (0 = none) *)
    rZWorld   : LREAL;          (* Working Z in world [mm]: belt height for
                                   products, layer Z for placement targets *)
    tAgeMs    : UDINT;          (* Age since capture [ms], for timeouts *)
    bValid    : BOOL;
END_STRUCT
END_TYPE

TYPE ST_SP_ResReq :
STRUCT
    iRobotId  : SINT;           (* Requesting robot (1..GC_ROBOTS) *)
    rRangeFrom: LREAL;          (* Robot work range, belt Y offset [mm] *)
    rRangeTo  : LREAL;          (* Robot work range, belt Y offset [mm] *)
    uiTypeId  : UINT;           (* Required type, 0 = any *)
    bTargetOnly: BOOL;          (* TRUE = only placement targets *)
    rMaxWeight: REAL;           (* Tool capacity [g], 0 = unlimited *)
END_STRUCT
END_TYPE

TYPE ST_SP_ResRsp :
STRUCT
    bOk      : BOOL;            (* Reservation granted *)
    iIdx     : SINT;            (* Queue index of the reserved item *)
    stItem   : ST_SP_TrkItem;   (* Snapshot of the reserved item *)
    p3Pick   : ST_SP_Pose3D;    (* Predicted world pick pose (pick line) *)
    rBeltSpd : LREAL;           (* Belt speed at reservation [mm/s] *)
END_STRUCT
END_TYPE

TYPE ST_SP_TrkCfg :
STRUCT
    bUsed     : BOOL;           (* Feed enabled *)
    sName     : STRING(16);     (* Human readable feed name *)
    iDir      : SINT;           (* Belt direction sign (+1 / -1) *)
    rWinStart : LREAL;          (* Distance pick line -> window start [mm] *)
    rWinLen   : LREAL;          (* Tracking window length [mm] *)
    rPickAhead: LREAL;          (* Reservation cut-off ahead of pick line [mm] *)
    tTimeout  : TIME;           (* Item tracking timeout *)
    astCalib  : ARRAY[1..GC_CAMS] OF ST_SP_Transf2D; (* Camera -> feed world *)
    stWorld   : ST_SP_Transf2D; (* Feed -> robot world frame (misalignment compensation) *)
    rZBelt    : LREAL;          (* Belt surface height in world frame [mm] *)
END_STRUCT
END_TYPE

TYPE ST_SP_TrkStat :
STRUCT
    uiTracked : UINT;           (* Items currently tracked *)
    uiReserved: UINT;           (* Items reserved by robots *)
    udiFed    : UDINT;          (* Total items fed into the queue *)
    udiPicked : UDINT;          (* Total items picked *)
    udiLost   : UDINT;          (* Items lost (timeout / window exit) *)
    bWindowBusy: BOOL;          (* Window saturated (backpressure signal) *)
END_STRUCT
END_TYPE
