(* =============================================================================
   SmartPick_iC - Vision-Guided High-Speed Picking Suite
   Target: Yaskawa iC 9226M-EC (iCube Engineer) | IEC 61131-3 Structured Text
   -----------------------------------------------------------------------------
   Module    : 01_Common
   Worksheet : FB - SP_AlarmMgr
   -----------------------------------------------------------------------------
   Purpose   : Central alarm registry with raise / clear / acknowledge
               lifecycle, occurrence counting and HMI list extraction.
               Alarm id semantics: uiId > 0, module-specific (see module
               header tables in the architecture guide).
   -----------------------------------------------------------------------------
   Methods   : Raise(uiId, eSrc, sText, eLevel) : BOOL - set active
               (TRUE = new record, FALSE = existing bumped)
               Clear(uiId) : BOOL - mark cleared (TRUE = found)
               Ack(uiId) : BOOL / AckAll : UINT (count acknowledged)
               GetEntry(iIdx) : BOOL - copy alarm record to out_stAlarm
               GetActive(iFromId) : BOOL - first active with id >= iFromId
               ActiveCount() : UINT - number of active (not acked) alarms
   -----------------------------------------------------------------------------
   Design    : Fixed registry, no dynamic memory; slot reuse on re-raise.
   =============================================================================
*)

FUNCTION_BLOCK SP_AlarmMgr
(* ----------------------------- Interface ------------------------------- *)
VAR_INPUT
    stNow : Yt_YA_RTC_Struct;         (* Wall clock stamp (from TaskSvc) *)
END_VAR
VAR_OUTPUT
    uiActive : UINT;                  (* Active, not yet acknowledged *)
    uiStored : UINT;                  (* Records currently in registry *)
END_VAR
VAR
    (* Fixed alarm registry (slot reuse, no dynamic memory) *)
    m_astReg  : ARRAY[1..GC_ALARM_N] OF ST_SP_Alarm;
    m_iCnt    : UINT := 0;            (* Used registry slots *)
    m_udiAcks : UDINT := 0;           (* Total acknowledge events *)
    out_stAlarm : ST_SP_Alarm;        (* Result buffer of GetEntry *)
END_VAR

(* ------------------------------- Body ---------------------------------- *)
(* Passive FB: lifecycle is driven through methods; body publishes counters. *)
uiActive := THIS.ActiveCount();
uiStored := m_iCnt;
END_FUNCTION_BLOCK


(* -----------------------------------------------------------------------
   METHOD: ActiveCount (parent SP_AlarmMgr) - internal helper
   Count active (Active state) alarms.
   ----------------------------------------------------------------------- *)
METHOD ActiveCount : UINT
VAR
    (* Loop index over registry slots (ActiveCount) *)
    i : UINT;
    (* Active-alarm counter accumulated during the scan *)
    uiC : UINT;
END_VAR
    uiC := 0;
    FOR i := 1 TO m_iCnt DO
        IF m_astReg[i].eState = ET_SP_AckState#Active THEN
            uiC := uiC + 1;
        END_IF
    END_FOR
    ActiveCount := uiC;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Raise (parent SP_AlarmMgr)
   Activate alarm uiId. If already present: bump occurrence counter and
   restore Active state when it was Acked but still not cleared.
   ----------------------------------------------------------------------- *)
METHOD Raise : BOOL
VAR_INPUT
    (* Id of the alarm to deactivate *)
    uiId  : UINT;
    (* Originating module tag *)
    eSrc  : ET_SP_LogSource;
    (* Severity shown on HMI / in the log *)
    eLevel: ET_SP_LogLevel;
    (* Short operator-facing description *)
    sText : STRING(80);
END_VAR
VAR
    (* Loop index over registry slots (Raise) *)
    i     : UINT;
    (* Target slot for a new record (0 = none found yet) *)
    iFree : UINT;
    (* TRUE when the alarm id already exists *)
    bHit  : BOOL;
END_VAR
    Raise := FALSE;                 (* Default: existing record bumped *)
    IF uiId = 0 THEN
        RETURN;    (* 0 is reserved as "no alarm" *)
    END_IF

    (* Look for an existing record first *)
    bHit  := FALSE;
    iFree := 0;
    FOR i := 1 TO m_iCnt DO
        IF m_astReg[i].uiId = uiId THEN
            bHit := TRUE;
            m_astReg[i].udiCnt := m_astReg[i].udiCnt + 1;
            IF m_astReg[i].eState <> ET_SP_AckState#Inactive THEN
                m_astReg[i].eState := ET_SP_AckState#Active;
                m_astReg[i].stRaised := stNow;
                m_astReg[i].stCleared := GC_stRtcNil;
            END_IF
            EXIT;
        END_IF
    END_FOR

    IF NOT bHit THEN
        (* Find free slot or append *)
        FOR i := 1 TO m_iCnt DO
            IF m_astReg[i].eState = ET_SP_AckState#Inactive THEN
                iFree := i;
                EXIT;
            END_IF
        END_FOR

        IF iFree = 0 THEN
            IF m_iCnt < UDINT_TO_UINT(GC_ALARM_N) THEN
                m_iCnt := m_iCnt + 1;
                iFree  := m_iCnt;
            ELSE
                (* Registry full: overwrite oldest cleared slot (slot 1) *)
                iFree := 1;
            END_IF
        END_IF

        m_astReg[iFree].uiId     := uiId;
        m_astReg[iFree].eState   := ET_SP_AckState#Active;
        m_astReg[iFree].eLevel   := eLevel;
        m_astReg[iFree].eSrc     := eSrc;
        m_astReg[iFree].sText    := sText;
        m_astReg[iFree].stRaised := stNow;
        m_astReg[iFree].stCleared:= GC_stRtcNil;
        m_astReg[iFree].udiCnt   := 1;
        Raise := TRUE;              (* New registry record created *)
    END_IF

    uiActive := THIS.ActiveCount();
    uiStored := m_iCnt;
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Clear (parent SP_AlarmMgr)
   Deactivate alarm uiId. Record remains with Inactive state for history.
   ----------------------------------------------------------------------- *)
METHOD Clear : BOOL
VAR_INPUT
    (* Id of the alarm to acknowledge *)
    uiId : UINT;
END_VAR
VAR
    (* Loop index over registry slots (Clear) *)
    i : UINT;
END_VAR
    Clear := FALSE;
    FOR i := 1 TO m_iCnt DO
        IF m_astReg[i].uiId = uiId THEN
            IF m_astReg[i].eState <> ET_SP_AckState#Inactive THEN
                m_astReg[i].eState := ET_SP_AckState#Inactive;
                m_astReg[i].stCleared := stNow;
                Clear := TRUE;      (* Matching record deactivated *)
            END_IF
            EXIT;
        END_IF
    END_FOR
    uiActive := THIS.ActiveCount();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: Ack (parent SP_AlarmMgr)
   Acknowledge one alarm (Active -> Acked until cleared).
   ----------------------------------------------------------------------- *)
METHOD Ack : BOOL
VAR_INPUT
    (* Id of the alarm to acknowledge *)
    uiId : UINT;
END_VAR
VAR
    (* Loop index over registry slots (Ack) *)
    i : UINT;
END_VAR
    Ack := FALSE;
    FOR i := 1 TO m_iCnt DO
        IF (m_astReg[i].uiId = uiId) AND (m_astReg[i].eState = ET_SP_AckState#Active) THEN
            m_astReg[i].eState := ET_SP_AckState#Acked;
            m_udiAcks := m_udiAcks + 1;
            Ack := TRUE;
            EXIT;
        END_IF
    END_FOR
    uiActive := THIS.ActiveCount();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: AckAll (parent SP_AlarmMgr)
   Acknowledge every active alarm.
   ----------------------------------------------------------------------- *)
METHOD AckAll : UINT
VAR
    (* Loop index over registry slots (AckAll) *)
    i : UINT;
END_VAR
    FOR i := 1 TO m_iCnt DO
        IF m_astReg[i].eState = ET_SP_AckState#Active THEN
            m_astReg[i].eState := ET_SP_AckState#Acked;
            m_udiAcks := m_udiAcks + 1;
            AckAll := AckAll + UINT#1;   (* Count of acknowledged alarms *)
        END_IF
    END_FOR
    uiActive := THIS.ActiveCount();
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetEntry (parent SP_AlarmMgr)
   Copy record iIdx (1-based) to out_stAlarm. TRUE on success.
   ----------------------------------------------------------------------- *)
METHOD GetEntry : BOOL
VAR_INPUT
    (* Registry position to copy (1-based) *)
    iIdx : UINT;
END_VAR
    GetEntry := FALSE;
    IF (iIdx >= 1) AND (iIdx <= m_iCnt) THEN
        out_stAlarm := m_astReg[iIdx];
        GetEntry := TRUE;
    END_IF
END_METHOD


(* -----------------------------------------------------------------------
   METHOD: GetActive (parent SP_AlarmMgr)
   Copy first active alarm with uiId >= iFromId (scan order) to out_stAlarm.
   Returns FALSE when none found (HMI polling pattern).
   ----------------------------------------------------------------------- *)
METHOD GetActive : BOOL
VAR_INPUT
    (* Scan starts from this id (HMI polling pattern) *)
    iFromId : UINT;
END_VAR
VAR
    (* Loop index over registry slots (GetActive) *)
    i : UINT;
END_VAR
    GetActive := FALSE;
    FOR i := 1 TO m_iCnt DO
        IF (m_astReg[i].eState = ET_SP_AckState#Active) AND (m_astReg[i].uiId >= iFromId) THEN
            out_stAlarm := m_astReg[i];
            GetActive := TRUE;
            EXIT;
        END_IF
    END_FOR
END_METHOD
