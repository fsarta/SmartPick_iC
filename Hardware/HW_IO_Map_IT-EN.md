# SmartPick_iC — HW I/O Map / Mappa I/O Fisica
**Chiusura punto aperto HW-3 — binding dei terminali fisici**
Target: Yaskawa iC 9226M-EC — iCube Engineer (EtherCAT)
Aggiornato: 2026-10-04

---

## 0. Principio / Principle

Il codice applicativo SmartPick **non tocca mai direttamente %I/%Q**: tutte
le seguenti variabili sono i **punti di frontiera** dichiarati in
`GVL_SP_Io` (e `GVL_SP_Prod` per assi/gruppi). Il binding fisico si fa
esclusivamente nella vista hardware di iCube Engineer (*Hardware → I/O
mapping*) collegando ogni variabile al terminale del coupler EtherCAT.
/ The SmartPick application code **never touches %I/%Q directly**: every
variable below is a **boundary point** declared in `GVL_SP_Io` (and
`GVL_SP_Prod` for axes/groups). Physical binding is done exclusively in
the iCube Engineer hardware view (*Hardware → I/O mapping*) by linking each
variable to the EtherCAT coupler terminal.

> Gli indirizzi `%I..`/`%Q..` nella tabella sono **suggeriti e progressivi**:
> adattarli al coupler reale (es. Yaskawa I/O Modules o Beckhoff EL1xxx/EL2xxx).
> / The `%I..`/`%Q..` addresses in the table are **suggested, sequential**:
> adapt them to the real coupler (e.g. Yaskawa I/O Modules or Beckhoff
> EL1xxx/EL2xxx).

---

## 1. Sicurezza / Safety chain

| Segnale | Variabile | Tipo | Indirizzo suggerito | Note |
|---|---|---|---|---|
| E-stop chain OK | `GVL_SP_Io.bEStopOk` | BOOL in | `%IX0.0` | Contatto pulito NC in serie; FALSE = arresto |
| Ripari / scanner OK | `GVL_SP_Io.bSafetyOk` | BOOL in | `%IX0.1` | Porte celle, light curtain |
| Reset segnalazioni | (HMI) | BOOL in | — | Da pannello operatore, non da %I |

**Regola / Rule:** `bEStopOk`/`bSafetyOk` FALSE arrestano il sistema con la
sequenza Stopping di `SP_System`; le uscite tool vengono messe OFF da
`SP_ToolCtl.AbortAll`. Verificare TC-01 della guida.
/ FALSE `bEStopOk`/`bSafetyOk` stop the system through the `SP_System`
Stopping sequence; tool outputs go OFF via `SP_ToolCtl.AbortAll`. Check
guide test TC-01.

---

## 2. Canali tool — 4 robot × 4 tool (MotoPick 4 spec)

Convenzione canale automatica: `canale = (robot − 1) × 4 + tool` (1..16).
/ Automatic channel convention: `channel = (robot − 1) × 4 + tool` (1..16).

| Canale | Uscita PICK (`abPickOut`) | Uscita PLACE (`abPlaceOut`) | Ingresso FBK (`abToolFbkIn`) |
|---|---|---|---|
| 1 (R1/T1) | `%QX2.0` | `%QX2.1` | `%IX2.0` |
| 2 (R1/T2) | `%QX2.2` | `%QX2.3` | `%IX2.1` |
| 3 (R1/T3) | `%QX2.4` | `%QX2.5` | `%IX2.2` |
| 4 (R1/T4) | `%QX2.6` | `%QX2.7` | `%IX2.3` |
| 5..8 (R2/T1..4) | `%QX3.*` | `%QX3.*` | `%IX3.*` |
| 9..12 (R3/T1..4) | `%QX4.*` | `%QX4.*` | `%IX4.*` |
| 13..16 (R4/T1..4) | `%QX5.*` | `%QX5.*` | `%IX5.*` |

Note / Notes:
- **PICK** e **PLACE** sono comandi separati (MotoPick 4): per le ventose
  tipicamente PICK = vacuum valve, PLACE = blow-off. Per pinza meccanica
  usare PICK = grip, PLACE = release.
  / **PICK** and **PLACE** are separate commands (MotoPick 4): suction cups
  typically PICK = vacuum valve, PLACE = blow-off; mechanical gripper
  PICK = grip, PLACE = release.
- **FBK** = pressostato vacuum / fine corsa grip. In **simulazione** il
  feedback è automaticamente loopback dell'uscita PICK (`PRG_SP_TaskFast`
  sezione 6); sul campo va cablato l'ingresso reale.
  / **FBK** = vacuum switch / grip end-of-travel. In **simulation** the
  feedback loops back from the PICK output (`PRG_SP_TaskFast` section 6); on
  site wire the real input.
- I canali 0 nelle config tool = mappatura automatica; canale esplicito si
  imposta in `g_astRobCfg[x].astTools[t].uiPickOutCh/uiPlaceOutCh/uiFbkInCh`.
  / Channel 0 in tool config = automatic mapping; explicit channel via
  `g_astRobCfg[x].astTools[t].uiPickOutCh/uiPlaceOutCh/uiFbkInCh`.

---

## 3. Convoglio — drive e sensori (8 linee)

| Linea | Analog out (drive 0) | Uscita impulsi (drive 1) | Sensore vaschetta (`abTraySensor`) |
|---|---|---|---|
| 1 | `%QW0` | asse servo via `MC_MoveVelocity` | `%IX6.0` |
| 2 | `%QW2` | idem | `%IX6.1` |
| 3 | `%QW4` | idem | `%IX6.2` |
| 4 | `%QW6` | idem | `%IX6.3` |
| 5 | `%QW8` | idem | `%IX6.4` |
| 6 | `%QW10` | idem | `%IX6.5` |
| 7 (uscita) | `%QW12` | idem | `%IX6.6` |
| 8 (uscita) | `%QW14` | idem | `%IX6.7` |

Note / Notes:
- `g_astConvCfg[x].eDrive` seleziona la modalità per linea:
  **0 = Analog** (VFD, canale `uiAnaCh`), **1 = ServoAxis** (`MC_MoveVelocity`
  sull'asse nastro), **2 = External** (velocità comandata da altro PLC).
  / `eDrive` selects the per-line mode: **0 Analog**, **1 ServoAxis**,
  **2 External**.
- Il fattore analogico è 0.0..1.0 della `rMaxSpeed` della ricetta; scalare
  nella configurazione del terminale (es. 0..10 V = 0..50 Hz).
  / The analog factor is 0.0..1.0 of the recipe `rMaxSpeed`; scale in the
  terminal config (e.g. 0..10 V = 0..50 Hz).
- `abTraySensor` è usato solo dalle linee uscita (7/8) con `BATCH` trigger
  mode 1 (Sensor). / Only outfeeds 7/8 use `abTraySensor` (BATCH trigger
  mode 1).

---

## 4. Encoder di linea / Conveyor encoders

| Linea | Binding firmware | Nota |
|---|---|---|
| 1..8 | `g_aAxisEnc[1..8] : AXIS_REF` | Asse encoder EtherCAT (o asse nastro se servo) nel catalogo hardware |

Configurazione consigliata / Recommended setup:
- Unità asse = **mm** (o scalare con `rEncScale` della ricetta: mm/impulso).
  / Axis unit = **mm** (or scale via recipe `rEncScale`: mm per count).
- Direzione: `iDir` nella ricetta (+1/−1) compensa encoder montato inverso.
  / Direction: recipe `iDir` (+1/−1) compensates a reversed encoder.
- 4 linee infeed + 2 outfeed nella configurazione 2; 8 nella configurazione 1
  di `PRG_SP_ConfigInit`.
  / 4 infeeds + 2 outfeeds in configuration 2; 8 in configuration 1 of
  `PRG_SP_ConfigInit`.

---

## 5. Gruppi cinematici robot / Robot kinematic groups

| Robot | Binding firmware | Nome suggerito catalogo |
|---|---|---|
| 1..4 | `g_aGrp[1..4] : AXES_GROUP_REF` | `Group1`..`Group4` (3 assi Cartesiani ciascuno, cart 2D + Z) |

- Stato gruppo (FW-2): vedi `Firmware/FW_PATCH_ConveyorTracking_IT-EN.md` §1.
  / Group status (FW-2): see the FW patch worksheet §1.
- Homing a livello asse: eseguirlo nel programma macchina/integratore prima
  di `bHomeAll`; `SP_Robot` si aspetta il gruppo referenziato.
  / Axis-level homing: run it in the machine/integrator program before
  `bHomeAll`; `SP_Robot` expects the group referenced.

---

## 6. Camere / Cameras (trigger esterno, opzionale)

| Segnale | Variabile | Direzione | Nota |
|---|---|---|---|
| Trigger out cam 1 | `%QX8.0` | out | Solo se `eTrig = 1 (External)`; altrimenti il trigger è distanza/intervallo via TCP |
| Trigger out cam 2 | `%QX8.1` | out | idem |
| Trigger in (fotoocella feed) | `%IX8.0` | in | Opzionale: `eTrig = 1` della CAMMAP |

Il collegamento camere è **Ethernet/TCP** (non EtherCAT): IP/porta nella
ricetta (`CAM` record) o preset `FUN_SP_CamPreset` (HW-4).
/ Cameras connect over **Ethernet/TCP** (not EtherCAT): IP/port in the
recipe (`CAM` record) or the `FUN_SP_CamPreset` presets (HW-4).

---

## 7. Configurazione task / Task configuration

| Parametro | Valore | Note |
|---|---|---|
| Task di `PRG_SP_TaskFast` | **2 ms, motion-critical** (v1.6: vedi `00_TaskConfig_IT-EN.md`) | `g_uiDtMs := UDINT#2` in `GVL_SP_Prod` — CONFIRM con la task config reale |
| Watchdog task | ≥ 2 × periodo | allarme `ErrIo` su overflow |
| Orologio controllore (v1.8) | `PRG_SP_TaskSvc` sezione 1 | wall clock da `Y_YA_RealTimeClock` (libreria Y_Yaskawa_Toolbox, da aggiungere ai riferimenti progetto); fallback automatico sul tick in simulazione/fault; durate dal tick monotono `g_udiTickMs` (`PRG_SP_TaskFast` sezione 1) |
| Retain | `g_stRetain` (VAR RETAIN) | persistenza power-fail, gestita da `SP_RetainMgr` |

---

## 8. Checklist di messa in servizio / Commissioning checklist

- [ ] Mappare i 18 ingressi digitali (estop, safety, 16 FBK tool)
      / Map the 18 digital inputs (estop, safety, 16 tool FBK)
- [ ] Mappare le 32 uscite digitali (16 PICK + 16 PLACE)
      / Map the 32 digital outputs (16 PICK + 16 PLACE)
- [ ] Mappare gli 8 analog out drive + canali `uiAnaCh` ricetta
      / Map the 8 analog drive outputs + recipe `uiAnaCh` channels
- [ ] Mappare i 8 sensori vaschetta
      / Map the 8 tray sensors
- [ ] Configurare i 4 gruppi cinematici e i 8 assi encoder
      / Configure the 4 kinematic groups and 8 encoder axes
- [ ] Applicare la configurazione 2 (`PRG_SP_ConfigInit`), adattare IP/porta camere
      / Apply configuration 2 (`PRG_SP_ConfigInit`), adapt camera IP/port
- [ ] Sequenza TC-01..TC-04 della guida (sicurezza, encoder, enable, home)
      / Run guide tests TC-01..TC-04 (safety, encoder, enable, home)
- [ ] Abilitare verifica prese (`bVerifyPick`) solo dopo FBK verificati
      / Enable `bVerifyPick` only after FBK is proven
- [ ] Se 2 robot condividono un'area: configurare `g_aiFeedZone` + `bZoneGuard`
      / If 2 robots share an area: set `g_aiFeedZone` + `bZoneGuard`
