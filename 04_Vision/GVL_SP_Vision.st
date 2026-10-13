(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 04_Vision
   Worksheet : GVL - GVL_SP_Vision
   -----------------------------------------------------------------------------
   Purpose   : Vision module constants: socket buffer sizing and the
               printable-ASCII lookup table used by FUN_SP_ByteCh to convert
               received TCP bytes into strings without pointer arithmetic
               outside the adapters.
   =============================================================================
*)

VAR CONSTANT
    GC_SOCK_RX : DINT := 512;   (* Socket receive buffer size [bytes] *)
    GC_SOCK_TX : DINT := 128;   (* Socket transmit buffer size [bytes] *)
    GC_VIS_MAX : SINT := 16;    (* Max items parsed per image *)
    GC_VIS_MAX2: SINT := 32;    (* Camera out-queue depth (harvest) *)
    GC_VIS_IDLE: UDINT := 60;   (* Idle time considered end-of-response [ms] *)
END_VAR
