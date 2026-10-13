(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 13_MultiGrip
   Worksheet : DUT - ST_SP_MultiGrip
   -----------------------------------------------------------------------------
   Purpose   : Advanced multi-grip data model (roadmap R-07):

     - ET_SP_GripExec : execution class of a job. AsyncCup = classical
       cup-by-cup pick (one descent per item, MotoPick 4 base parity).
       SyncAll = ONE tracked descent with the whole gripper head: all
       cups fire together on a geometrically verified cluster.
     - ST_SP_ClReq    : cluster request filled by PRG_SP_TaskFast from the
       robot tool configuration (cup layout, tolerances, payload).
     - ST_SP_ClRsp    : cluster result produced by SP_ItemQueue with the
       SP_GripPlanner intelligence: selected queue slots, per-item
       reservation records, synchronized TCP pose, payload audit.

   Geometry model (belt-rigid clusters):
     All items of a cluster ride the same belt, so their RELATIVE
     positions are invariant between capture and pick (rigid translation
     along the belt axis). Matching therefore runs on the capture world
     poses; the synchronized pick event is defined as "anchor (front)
     item at the pick line", at which moment every member has translated
     by the anchor travel. This keeps the math deterministic and
     encoder-independent.
   =============================================================================
*)

TYPE ET_SP_GripExec :
(
    AsyncCup := 0,        (* Sequential cup-by-cup pick (base behavior) *)
    SyncAll  := 1         (* One synchronized descent on a matched cluster *)
);
END_TYPE

TYPE ST_SP_ClReq :
STRUCT
    (* Who is asking and from where (mirrors ST_SP_ResReq filters) *)
    iRobotId  : SINT;           (* Requesting robot 1..GC_ROBOTS *)
    rRangeFrom: LREAL;          (* Robot work range, belt offset [mm] *)
    rRangeTo  : LREAL;          (* Robot work range, belt offset [mm] *)
    uiTypeId  : UINT;           (* Required type, 0 = any *)
    rMaxWeight: LREAL;          (* Tool payload capacity [g], 0 = unlimited *)
    (* Gripper head geometry (tool frame, TCP at cup 1 reference) *)
    uiCups    : UINT;           (* Active cups offered to the planner 1..GC_CUPS *)
    astCup    : ARRAY[1..4] OF ST_SP_Point3D; (* Cup offsets rel. TCP [mm] 1..GC_CUPS *)
    (* Cluster rules *)
    bSingleType : BOOL;         (* TRUE = no mixed product types per cluster *)
    rMatchTol   : LREAL;        (* Max cup-to-item residual [mm] *)
    rMinGap     : LREAL;        (* Min distance between picked items [mm], 0 = off *)
    rMaxCog     : LREAL;        (* Max CoG offset from TCP [mm], 0 = check off *)
END_STRUCT
END_TYPE

TYPE ST_SP_ClRsp :
STRUCT
    (* Cluster formation result (one per reservation handshake) *)
    bOk      : BOOL;            (* TRUE = at least the anchor was reserved *)
    bSync    : BOOL;            (* TRUE = synchronized multi-pick possible *)
    uiN      : UINT;            (* Members reserved 1..GC_CUPS *)
    aiIdx    : ARRAY[1..4] OF SINT;   (* Queue slot per member 1..GC_CUPS *)
    aCup     : ARRAY[1..4] OF SINT;   (* Cup id per member (1-based) 1..GC_CUPS *)
    astRsp   : ARRAY[1..4] OF ST_SP_ResRsp; (* Per-member reservation 1..GC_CUPS *)
    stTcp    : ST_SP_Pose3D;    (* Synchronized TCP pose at the pick event *)
    rTotWeight : LREAL;         (* Cluster total weight [g], 0 = unknown *)
    rCogOff  : LREAL;           (* CoG offset from TCP [mm] (0 = unknown) *)
END_STRUCT
END_TYPE
