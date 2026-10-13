(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 02_Geometry
   Worksheet : DUT - ST_SP_Geometry
   -----------------------------------------------------------------------------
   Purpose   : 2D/3D pose primitives and similarity-transform descriptor used
               for camera-to-conveyor and conveyor-to-world frame mapping.
   -----------------------------------------------------------------------------
   Frame model:
     Parent frame = T o child frame, with T = ST_SP_Transf2D:
       X = dx + scale * ( cos(rot)*x - sin(rot)*y )
       Y = dy + scale * ( sin(rot)*x + cos(rot)*y )
       th= rot + th_child
     UNITS (v1.7.0): distances in [mm], ALL angles (rot, th) in DEGREES.
     The cos/sin evaluations inside FUN_SP_Geometry convert deg -> rad
     with GC_DEG2RAD at the call site (IEC trig functions are radian-based).
     Applied via FUN_SP_TrfX / FUN_SP_TrfY / FUN_SP_TrfTh (02_Geometry).
   =============================================================================
*)

TYPE ST_SP_Point2D :
STRUCT
    rX : LREAL;         (* X coordinate [mm] *)
    rY : LREAL;         (* Y coordinate [mm] *)
END_STRUCT
END_TYPE

TYPE ST_SP_Pose2D :
STRUCT
    rX  : LREAL;        (* X position [mm] *)
    rY  : LREAL;        (* Y position [mm] *)
    rTh : LREAL;        (* Yaw angle [deg] *)
END_STRUCT
END_TYPE

TYPE ST_SP_Point3D :
STRUCT
    rX : LREAL;         (* X position [mm] *)
    rY : LREAL;         (* Y position [mm] *)
    rZ : LREAL;         (* Z position (height) [mm] *)
END_STRUCT
END_TYPE

TYPE ST_SP_Pose3D :
STRUCT
    rX  : LREAL;        (* X position [mm] *)
    rY  : LREAL;        (* Y position [mm] *)
    rZ  : LREAL;        (* Z position (height) [mm] *)
    rTh : LREAL;        (* C rotation around vertical axis [deg] *)
END_STRUCT
END_TYPE

TYPE ST_SP_Transf2D :
STRUCT
    rDx    : LREAL;     (* Translation X (parent frame) [mm] *)
    rDy    : LREAL;     (* Translation Y (parent frame) [mm] *)
    rRot   : LREAL;     (* Rotation child->parent [deg] *)
    rScale : LREAL;     (* Uniform scale child->parent [u_child/u_parent] *)
    bValid : BOOL;      (* TRUE after successful calibration *)
END_STRUCT
END_TYPE

TYPE ST_SP_CalibStat :
STRUCT
    iPairs : SINT;      (* Number of registered point pairs *)
    rRms   : LREAL;     (* RMS residual of the fit [user unit] *)
    bValid : BOOL;      (* TRUE when a valid transform is available *)
END_STRUCT
END_TYPE
