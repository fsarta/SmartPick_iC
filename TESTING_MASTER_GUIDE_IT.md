# SmartPick_iC — Manuale Maestro di Test e Validazione (Completo, Passo-Passo)

> **Progetto:** SmartPick_iC — sistema di picking ad alta velocità per Yaskawa iCube Engineer 2026.6  
> **Ambito documento:** procedura di collaudo, verifica e validazione di **OGNI** elemento del software: 73 fogli Structured Text, 81 tipi di dati (TYPE/DUT), 40 FUNCTION, 35 FUNCTION_BLOCK, 209 METHOD, 4 PROGRAM, 10 GVL, 8 configurazioni di sistema, 25 fault-injection test e 14 protocolli di benchmark "Prima vs Dopo".  
> **Lingua:** Italiano (commenti tecnici in inglese come da standard di progetto).  
> **Metodo:** V-Model bottom-up — nessun livello superiore viene aperto se il livello inferiore non è certificato al 100%.

---

## Come si usa questo manuale

1. Il manuale è **sequenziale**: si esegue dalla Sezione 0 in avanti. Ogni test ha un ID univoco (`UT-*`, `FB-*`, `PRG-*`, `INT-*`, `FT-*`, `BM-*`).
2. Ogni test dichiara **precondizioni, passi numerati, valori di stimolo, risultati attesi al valore esatto e criterio GO/NO-GO**.
3. Per ogni test va compilato il **Registro Esiti** (Appendice C) con: ID, data/ora, operatore, esito (PASS/FAIL), valori misurati, note.
4. Un test FAIL blocca la progressione: si corregge il codice, si rigenera il binario, si **ripete l'intera sezione** dal suo primo test.
5. Dove il test richiede il macchinario reale è marcato **[HW]**; tutti gli altri sono eseguibili interamente in simulazione (`eMode = ET_SP_Mode#Simulated`) o con i simulatori integrati (`SP_SimCamera`, `SP_SimConveyor`).

---

## Indice Generale

| Sezione | Contenuto | ID test |
|---|---|---|
| 0 | Metodologia, ambiente, Watch Table, criteri GO/NO-GO | `SET-*` |
| 1 | Unit Test delle 40 FUNCTION pure | `UT-F01` .. `UT-F40` |
| 2 | Unit Test dei DUT/TYPE e dei GVL | `UT-D01` .. `UT-D81`, `UT-G01` .. `UT-G10` |
| 3 | Test dei 35 FUNCTION_BLOCK in isolamento | `FB-T01` .. `FB-T35` |
| 4 | Matrice di copertura dei 209 METHOD | `M-*` |
| 5 | Test dei 4 PROGRAM e dei task ciclici | `PRG-T01` .. `PRG-T04` |
| 6 | Integrazione progressiva CFG 1 .. CFG 8 | `INT-1` .. `INT-8` |
| 7 | Fault Injection e Stress Test | `FT-01` .. `FT-25` |
| 8 | Benchmark "Prima vs Dopo" 14 funzionalità MotoPick | `BM-01` .. `BM-14` |
| 9 | Collaudo su macchina reale | `HW-*` |
| 10 | Criteri di accettazione finale e tracciabilità | — |
| App. A-D | Glossario, template Watch/CSV, registro anomalie, checklist importazione | — |

---

## Sezione 0 — Metodologia, Ambiente di Test e Regole Generali

### 0.1 Metodologia V-Model applicata a SmartPick_iC

La catena di verifica procede dal basso verso l'alto in 6 livelli. **Regola di sblocco:** il livello N+1 si apre solo con tutti i test del livello N in stato PASS registrato.

| Livello | Oggetto | Sezione | N. test | Sblocca |
|---|---|---|---|---|
| L0 | Preparazione ambiente e Watch Table | 0.2-0.5 | SET-01..12 | L1 |
| L1 | FUNCTION pure (40) — nessuno stato, nessun side-effect | 1 | UT-F01..F40 | L2 |
| L2 | DUT/TYPE (81) + GVL (10) | 2 | UT-D01..G10 | L3 |
| L3 | FUNCTION_BLOCK isolati (35) con i loro METHOD (209) | 3-4 | FB-T01..T35 | L4 |
| L4 | PROGRAM e scheduling 2/10/100 ms | 5 | PRG-T01..T04 | L5 |
| L5 | Integrazione CFG 1..CFG 8 | 6 | INT-1..INT-8 | L6 |
| L6 | Fault injection, stress, benchmark, collaudo HW | 7-9 | FT/BM/HW | Rilascio |


**Criterio di fermata:** ogni anomalia riportata in Appendice C con gravità `BLOCKER` o `MAJOR` impedisce il passaggio al livello successivo. Le anomalie `MINOR` possono essere pianificate ma vanno comunque chiuse prima del Rilascio.

---

### 0.2 Preparazione dell'ambiente iCube Engineer 2026.6 (`SET-01` .. `SET-12`)

Eseguire **una volta sola** prima di ogni campagna di test. Compilare il Registro Esiti per ogni passo.

| ID | Attività | Procedura passo-passo | Risultato atteso |
|---|---|---|---|
| SET-01 | Creazione progetto | Nuovo progetto iCube Engineer 2026.6 → target CPU Yaskawa RCX/MLX compatibile iCube 2026.6 → nome `SmartPick_iC_Test`. Impostare ciclo minimo task ≥ 2 ms. | Progetto creato, zero errori di compilazione iniziale. |
| SET-02 | Importazione fogli ST | Seguire `00_ImportOrder.st` e l'Appendice D: importare i 73 fogli nell'ordine esatto (GVL/DUT prima dei FB, FB prima dei PRG). | 73 fogli presenti, albero progetto come da Appendix D. |
| SET-03 | Compilazione ordinata | Compilare con "Check all" attivo. Eventuali errori vanno risolti SOLO con le regole di progetto (no puntatori, no ADR, no ACTION, no array di FB, no VAR_IN_OUT nei METHOD, no ricorsione). | Zero errori, zero warning di tipo/compatibilità iCube 2026.6. |
| SET-04 | Task configuration | Creare 3 task ciclici: `T_Fast` = 2 ms (PRG_SP_TaskFast), `T_Main` = 10 ms (PRG_SP_TaskMain), `T_Svc` = 100 ms (PRG_SP_TaskSvc). Watchdog del task Fast ≥ 6 ms, Main ≥ 30 ms, Svc ≥ 300 ms. | 3 task attivi, nessun warning di sovrapposizione. |
| SET-05 | Configurazione iniziale | Eseguire `PRG_SP_ConfigInit` all’avvio (prima esecuzione). Verificare che `stSys.eMode = Simulated`, `stSys.bAuto = FALSE`, tutti i robot `eState = Disabled`. | Sistema in `Idle`, `stSys.eMode=Simulated`, `stSys.eMode=Simulated`. |
| SET-06 | Watch Table | Creare le 4 Watch Table descritte in 0.3 (WT1..WT4) con le variabili elencate. | 4 WT salvate nel progetto. |
| SET-07 | Simulazione visione | Verificare che `SimCam1`/`SimCam2` (`SP_SimCamera`) siano configurati con `bUsed=TRUE` nelle rispettive camere di `GVL_SP_Inst.stCam` (driver `Simulated`). | Scatto simulato produce ≥1 item. |
| SET-08 | Simulazione nastro | Verificare `SimConv1` (`SP_SimConveyor`) su `stConv[1]`: `bSim=TRUE`, `rBeltSpeed` default 450 mm/s. | Encoder simulato avanza con il nastro. |
| SET-09 | RTC e tick | Leggere `GVL_SP_Rtc` (`stRtc`, `udiTickMs`) e verificare monotonia crescente del tick. | Tick monotono, `stRtc` plausibile. |
| SET-10 | Log e allarmi | Verificare `SP_Logger` (capacità `GC_LOG_N` = 256 voci) e `SP_AlarmMgr` (64 voci): eseguire `Logger.LogInfo` e `AlarmMgr.Raise` di prova. | Entrambe le code registrano e leggono la voce di prova. |
| SET-11 | Sicurezza soft | Con il simulatore, verificare che `bEStop=FALSE` blocchi ogni movimento (`stSys.bMotionPermit`). Impostare `rBeltSpeed` e velocità robot ai valori minimi per la campagna di test di fabbrica. | Blocco E-Stop efficace già in simulazione. |
| SET-12 | Baseline dati | Esportare la configurazione di default con `SP_RecipeMgr` (`ExportBegin`+`ExportNext`) in `baseline.cfg`, salvare checksum `SP_RetainMgr.ChkSum`. | File `baseline.cfg` presente, checksum annotato. |

**Regole di esecuzione comuni a tutti i test seguenti:**

1. Prima di ogni test: `SP_System.ResetAll` non esistendo come metodo globale, usare `SP_System.Step` in `Idle` con `bReset=TRUE` su `stHmi` (vedi `FB_SP_System`) e verificare `stSys.eState = Idle`.
2. Trascrivere su Registro Esiti: ID test, data/ora (da `GVL_SP_Rtc`), operatore, esito, valori misurati (dalle Watch Table), commento.
3. Se un test richiede l'azzeramento di contatori, usare i metodi dedicati (`SP_Stats.Reset`, `SP_Oee.Reset`, `SP_Maint.ResetAll`, `SP_ItemQueue.ClearAll`, `SP_BatchMgr.ClearAll`) — **mai** forzare a mano variabili interne dei FB.
4. Ogni cambiamento di codice dopo un FAIL richiede: ricompilazione → reinstall → rilancio del test fallito **e di tutti i test della stessa sezione**.
5. Per i test [HW]: allineare sempre `stConv[i].rBeltSpeed` con la velocità reale misurata dal sensore (tacche/enc) prima di procedere.

---

### 0.3 Le 4 Watch Table di collaudo (variabili esatte)

In iCube Engineer: `Online → Watch and Force Tables → New`. Inserire le variabili con i percorsi completi `NomeGVL.Variabile`. Colonne consigliate: *Name | Value | Force | Comment*.

#### WT_1_Comandi_Stato — comando e stato macchina

| Percorso variabile | Tipo | Uso nel test |
|---|---|---|
| GVL_SP_Hmi.stHmi.bStart | BOOL | Avvio ciclo automatico |
| GVL_SP_Hmi.stHmi.bStop | BOOL | Stop a fine ciclo |
| GVL_SP_Hmi.stHmi.bReset | BOOL | Reset allarmi/ripristino |
| GVL_SP_Hmi.stHmi.bEStop | BOOL | Emergenza (fault injection) |
| GVL_SP_Hmi.stHmi.bAuto | BOOL | Selezione Auto/Manuale |
| GVL_SP_Hmi.stHmi.bResilience | BOOL | Migrazione carico su perdita robot |
| GVL_SP_Hmi.stHmi.bPause | BOOL | Pausa produzione |
| GVL_SP_Prod.stSys.eState | ET_SP_SysState | Stato FSM sistema |
| GVL_SP_Prod.stSys.eMode | ET_SP_Mode | Simulated / Auto / Service |
| GVL_SP_Prod.stSys.bMotionPermit | BOOL | Permesso movimento |
| GVL_SP_Prod.stSys.udiCycleMs | UDINT | Ciclo medio (KPI) |
| GVL_SP_Rtc.udiTickMs | UDINT | Base tempi test |

#### WT_2_Nastri_Visione_Code — infeed, camere, tracking

| Percorso variabile | Tipo | Uso nel test |
|---|---|---|
| GVL_SP_Io.stConv[1].rReqFactor | LREAL | Fattore di pacing richiesto |
| GVL_SP_Io.stConv[1].rBeltSpeed | LREAL | Velocità nastro (mm/s) |
| GVL_SP_Io.stConv[1].bEnable | BOOL | Abilitazione motore |
| GVL_SP_Trk.gastItemQ[1].stOut.uiTracked | UINT | Pezzi tracciati coda 1 |
| GVL_SP_Trk.gastItemQ[1].stOut.udiDup | UDINT | Doppioni rilevati coda 1 |
| GVL_SP_Trk.gastItemQ[1].stOut.udiFed | UDINT | Pezzi immessi coda 1 |
| GVL_SP_Inst.stCam[1].stOut.uiItems | UINT | Item ultimo scatto cam 1 |
| GVL_SP_Inst.stCam[1].stOut.bValid | BOOL | Scatto valido |
| GVL_SP_Inst.stCam[1].stStat.udiTimeout | UDINT | Timeout camera 1 |
| GVL_SP_Trk.gastItemQ[1].stOut.udiRes | UDINT | Pezzi riservati |

#### WT_3_Robot_Collisioni — robot, attrezzi, zone

| Percorso variabile | Tipo | Uso nel test |
|---|---|---|
| GVL_SP_Inst.astRob[1].stOut.eState | ET_SP_RobState | Stato robot 1 |
| GVL_SP_Inst.astRob[1].stOut.uiCycleMs | UINT | Tempo ciclo robot 1 |
| GVL_SP_Inst.astRob[1].stOut.udiPick | UDINT | Contatore pick |
| GVL_SP_Inst.astRob[1].stOut.bHolding[1] | BOOL | Ventosa 1 occupata |
| GVL_SP_Inst.stCol.stOut.bSlowRob[1] | BOOL | Rallentamento TCP robot 1 |
| GVL_SP_Inst.stCol.stOut.bStopRob[1] | BOOL | Stop TCP robot 1 |
| GVL_SP_Inst.stZone[1].stOut.bOccupied[1] | BOOL | Zona 1 occupata da robot 1 |
| GVL_SP_Prod.stSys.udiAbortFlight | UDINT | Aborti volo per pezzo perso |

#### WT_4_Batch_KPI_Allarmi — produzione, qualità, diagnostica

| Percorso variabile | Tipo | Uso nel test |
|---|---|---|
| GVL_SP_Prod.gastBatch[1].stDef.iMode | SINT | Modalità batch |
| GVL_SP_Prod.gastBatch[1].stStat.uiDone | UINT | Battute completate |
| GVL_SP_Prod.gastBatch[1].stStat.bComplete | BOOL | Batch completato |
| GVL_SP_Prod.stStats.uiFeedPerMin | UINT | Feed rate |
| GVL_SP_Prod.stStats.uiGood | UINT | Contatore good |
| GVL_SP_Prod.stStats.uiNo | UINT | Contatore NG |
| GVL_SP_Prod.stOee.rA / rP / rQ / rOee | LREAL | Componenti OEE |
| GVL_SP_Prod.gastAlarm[1].stOut.uiActive | UINT | Allarmi attivi |
| GVL_SP_Prod.gastAlarm[1].stOut.uiUnack | UINT | Allarmi non ack |
| GVL_SP_Prod.stLog.stOut.uiCount | UINT | Voci di log presenti |


---

### 0.4 Template Registro Esiti e criteri GO/NO-GO

| Colonna | Contenuto |
|---|---|
| ID | Es. `UT-F07` o `INT-3` |
| Data/Ora | `stRtc` formato `YYYY-MM-DD hh:mm:ss` |
| Operatore | Nome/iniziali |
| Ver. firmware | GC_SP_VER_MAJOR.MINOR.BUILD = 1.8.0 |
| Esito | PASS / FAIL / BLOCKED |
| Valori misurati | Snapshot delle Watch Table prima/dopo |
| Anomalie | ID Appendice C oppure `-` |
| Firma | Iniziali operatore |


**Definizioni:**

- **PASS**: tutti i risultati attesi rispettati entro le tolleranze indicate (numeriche: ±0.001 su LREAL di calcolo, ±1 su conteggi, esatte su stringhe/enum/bool).
- **FAIL**: anche un solo risultato atteso non rispettato.
- **BLOCKED**: precondizione non ottenibile (es. assenza HW) — va ri-eseguito appena disponibile.

---

### 0.5 Matrice di copertura del codice (73 fogli ST)

Elenco completo dei fogli con i contenuti verificati dalle sezioni successive. La colonna "Test di riferimento" indica dove ogni elemento è collaudato.

| Foglio | Righe | TYPE | FUNCTION | F_BLOCK | METHOD | PROGRAM | Test di riferimento |
|---|---|---|---|---|---|---|---|
| 00_ImportOrder.st | 105 | 0 | 0 | 0 | 0 | 0 | Sez. 2 |
| 01_Common/DUT_SP_Enums_Common.st | 237 | 20 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 01_Common/DUT_SP_Structs_Common.st | 66 | 5 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 01_Common/FB_SP_AlarmMgr.st | 273 | 0 | 0 | 1 | 7 | 0 | Sez. 3 (FB-T) — isolamento |
| 01_Common/FB_SP_Logger.st | 223 | 0 | 0 | 1 | 7 | 0 | Sez. 3 (FB-T) — isolamento |
| 01_Common/FB_SP_MovAvg.st | 60 | 0 | 0 | 1 | 0 | 0 | Sez. 3 (FB-T) — isolamento |
| 01_Common/FUN_SP_ByteCh.st | 31 | 0 | 1 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 01_Common/FUN_SP_Parse.st | 530 | 0 | 11 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 01_Common/FUN_SP_RtcToStr.st | 91 | 0 | 1 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 01_Common/FUN_SP_TickToRtc.st | 84 | 0 | 1 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 01_Common/FUN_SP_Utils.st | 302 | 0 | 13 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 01_Common/GVL_SP_Const.st | 79 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 02_Geometry/DUT_SP_Geometry.st | 71 | 6 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 02_Geometry/FB_SP_Calib2D.st | 209 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) — isolamento |
| 02_Geometry/FUN_SP_Geometry.st | 195 | 0 | 9 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 03_Conveyor/DUT_SP_ConveyorTypes.st | 45 | 2 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 03_Conveyor/FB_SP_ConvDrive.st | 87 | 0 | 0 | 1 | 0 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 03_Conveyor/FB_SP_ConvEncoder.st | 64 | 0 | 0 | 1 | 0 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 03_Conveyor/FB_SP_Conveyor.st | 180 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/DUT_SP_VisionTypes.st | 84 | 4 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 04_Vision/FB_SP_DrvAscii.st | 379 | 0 | 0 | 1 | 7 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FB_SP_DrvCognex.st | 120 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FB_SP_DrvGeneric.st | 110 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FB_SP_DrvKeyence.st | 119 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FB_SP_Socket.st | 224 | 0 | 0 | 1 | 4 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FB_SP_VisionCam.st | 415 | 0 | 0 | 1 | 8 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 04_Vision/FUN_SP_CamPreset.st | 90 | 0 | 1 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 04_Vision/GVL_SP_Vision.st | 21 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 05_Tracking/DUT_SP_TrkTypes.st | 93 | 5 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 05_Tracking/FB_SP_ItemQueue.st | 791 | 0 | 0 | 1 | 16 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 05_Tracking/FB_SP_TrkFeed.st | 308 | 0 | 0 | 1 | 11 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 05_Tracking/GVL_SP_Trk.st | 17 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 06_Pattern/DUT_SP_PatternTypes.st | 71 | 4 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 06_Pattern/FB_SP_BatchMgr.st | 327 | 0 | 0 | 1 | 11 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 06_Pattern/FB_SP_PatternGen.st | 418 | 0 | 0 | 1 | 10 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 07_LoadSharing/DUT_SP_ShareTypes.st | 52 | 3 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 07_LoadSharing/FB_SP_LoadBalancer.st | 343 | 0 | 0 | 1 | 7 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 07_LoadSharing/FB_SP_ZoneGuard.st | 173 | 0 | 0 | 1 | 1 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 08_Robot/DUT_SP_RobotTypes.st | 217 | 12 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 08_Robot/FB_SP_RobMotion.st | 503 | 0 | 0 | 1 | 1 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 08_Robot/FB_SP_Robot.st | 1548 | 0 | 0 | 1 | 26 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 08_Robot/FB_SP_ToolCtl.st | 462 | 0 | 0 | 1 | 17 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 09_Production/DUT_SP_SysTypes.st | 108 | 7 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 09_Production/FB_SP_Dispatch.st | 455 | 0 | 0 | 1 | 6 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 09_Production/FB_SP_Stats.st | 170 | 0 | 0 | 1 | 6 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 09_Production/FB_SP_System.st | 519 | 0 | 0 | 1 | 13 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 10_Persistence/DUT_SP_PersistTypes.st | 37 | 2 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 10_Persistence/FB_SP_FileIo.st | 219 | 0 | 0 | 1 | 5 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 10_Persistence/FB_SP_RecipeMgr.st | 713 | 0 | 0 | 1 | 13 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 10_Persistence/FB_SP_RetainMgr.st | 141 | 0 | 0 | 1 | 5 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 11_Simulation/FB_SP_SimCamera.st | 163 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 11_Simulation/FB_SP_SimConveyor.st | 41 | 0 | 0 | 1 | 0 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 12_Application/FUN_SP_RobCfgDefault.st | 139 | 0 | 1 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 12_Application/GVL_SP_Fw.st | 71 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Hmi.st | 69 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Inst.st | 42 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Io.st | 41 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Prod.st | 81 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Rtc.st | 63 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/GVL_SP_Sync.st | 62 | 0 | 0 | 0 | 0 | 0 | Sez. 2 (UT-G) |
| 12_Application/PRG_SP_ConfigInit.st | 1516 | 0 | 0 | 0 | 0 | 1 | Sez. 5 (PRG-T) |
| 12_Application/PRG_SP_TaskFast.st | 816 | 0 | 0 | 0 | 0 | 1 | Sez. 5 (PRG-T) |
| 12_Application/PRG_SP_TaskMain.st | 205 | 0 | 0 | 0 | 0 | 1 | Sez. 5 (PRG-T) |
| 12_Application/PRG_SP_TaskSvc.st | 302 | 0 | 0 | 0 | 0 | 1 | Sez. 5 (PRG-T) |
| 13_MultiGrip/DUT_SP_MultiGrip.st | 70 | 3 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 13_MultiGrip/FB_SP_GripPlanner.st | 410 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 13_MultiGrip/FUN_SP_ClusterMath.st | 99 | 0 | 2 | 0 | 0 | 0 | Sez. 1 (UT-F) |
| 14_Collision/DUT_SP_ColTypes.st | 71 | 4 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 14_Collision/FB_SP_Collision.st | 420 | 0 | 0 | 1 | 3 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 15_Professional/DUT_SP_ProTypes.st | 87 | 4 | 0 | 0 | 0 | 0 | Sez. 2 (UT-D) |
| 15_Professional/FB_SP_Maint.st | 187 | 0 | 0 | 1 | 1 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 15_Professional/FB_SP_Oee.st | 179 | 0 | 0 | 1 | 2 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |
| 15_Professional/FB_SP_SelfTest.st | 210 | 0 | 0 | 1 | 1 | 0 | Sez. 3 (FB-T) + Sez. 6 (INT) |

**Totali:** 73 fogli, 17523 righe di ST, 81 TYPE, 40 FUNCTION, 35 FUNCTION_BLOCK, 209 METHOD, 4 PROGRAM.

---

## Sezione 1 — Unit Test delle 40 FUNCTION pure (UT-F01 .. UT-F40)

Le FUNCTION non hanno stato interno: la verifica si riduce a **stimolo → risposta attesa**. Procedura standard per ogni test:

1. Aprire la Watch Table `WT_TestUnit` (crearla temporanea) e dichiarare le variabili di stimolo indicate nella scheda.
2. Scrivere i valori di stimolo nella colonna *Value*.
3. Creare nel progetto un PROGRAM temporaneo `PRG_UT_Scratch` (NON compilato nella release finale) con una chiamata alla FUNCTION in prova, assegnando il risultato a una variabile osservabile.
4. Eseguire un singolo ciclo di `PRG_UT_Scratch` (Run → Step).
5. Leggere il risultato in Watch e confrontarlo con la colonna *Atteso* entro tolleranza.
6. Registrare PASS/FAIL. Ripetere per tutti i casi della scheda.

Per ogni FUNCTION si fornisce: firma esatta (VAR_IN), semantica, tabella dei casi di test con valori esatti, procedura e criterio.

### UT-F01 — `FUN_SP_Clamp` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rVal | LREAL | - | Value to constrain |
| rLo | LREAL | - | Lower bound |
| rHi | LREAL | - | Upper bound |

**Tipo di ritorno:** `LREAL`

**Semantica:** Limita `rVal` nell'intervallo chiuso [rLo, rHi]. Se rLo>rHi il comportamento deterministico è: restituisce rLo quando rVal<rLo, altrimenti rHi quando rVal>rHi.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rVal=5.0, rLo=0.0, rHi=10.0 | 5.0 | Valore interno invariato. |
| 2 | rVal=-2.5, rLo=0.0, rHi=10.0 | 0.0 | Saturazione al minimo. |
| 3 | rVal=15.0, rLo=0.0, rHi=10.0 | 10.0 | Saturazione al massimo. |
| 4 | rVal=0.0, rLo=0.0, rHi=10.0 | 0.0 | Estremo inferiore incluso. |
| 5 | rVal=10.0, rLo=0.0, rHi=10.0 | 10.0 | Estremo superiore incluso. |
| 6 | rVal=7.0, rLo=10.0, rHi=0.0 | 10.0 | Intervalli invertiti: rVal<rLo → restituisce rLo (verificare come nota di progetto). |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Clamp(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F01:** PASS solo se tutti i 6 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F02 — `FUN_SP_ClampI` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| iVal | DINT | - | Value to constrain |
| iLo | DINT | - | Lower bound |
| iHi | DINT | - | Upper bound |

**Tipo di ritorno:** `DINT`

**Semantica:** Come Clamp su interi DINT (usato da DigCh/LRealToStr per gli indici).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | iVal=5, iLo=0, iHi=9 | 5 | In range. |
| 2 | iVal=-1, iLo=0, iHi=9 | 0 | Saturazione bassa. |
| 3 | iVal=12, iLo=0, iHi=9 | 9 | Saturazione alta. |
| 4 | iVal=-2147483648, iLo=-100, iHi=100 | -100 | Estremo DINT saturato correttamente (no overflow). |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_ClampI(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F02:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F03 — `FUN_SP_Deg2Rad` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rDeg | LREAL | - | Angle in degrees |

**Tipo di ritorno:** `LREAL`

**Semantica:** Conversione gradi → radianti con costante `GC_DEG2RAD = 0.01745329251994329577`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rDeg=180.0 | 3.141592653589793 | π |
| 2 | rDeg=0.0 | 0.0 | Zero. |
| 3 | rDeg=90.0 | 1.5707963267948966 | π/2 |
| 4 | rDeg=-45.0 | -0.7853981633974483 | Negativo. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Deg2Rad(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F03:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F04 — `FUN_SP_Rad2Deg` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rRad | LREAL | - | Angle in radians |

**Tipo di ritorno:** `LREAL`

**Semantica:** Conversione radianti → gradi con `GC_RAD2DEG = 57.29577951308232087680`. Verifica di simmetria con UT-F03.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rRad=3.141592653589793 | 180.0 | ±0.001 |
| 2 | rRad=0.0 | 0.0 | Zero. |
| 3 | rRad=1.5707963267948966 | 90.0 | ±0.001 |
| 4 | Rad2Deg(Deg2Rad(37.5)) | 37.5 | Round-trip entro ±1e-9. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Rad2Deg(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F04:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F05 — `FUN_SP_Atan2` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rY | LREAL | - | Y coordinate (ordinate) |
| rX | LREAL | - | X coordinate (abscissa) |

**Tipo di ritorno:** `LREAL`

**Semantica:** Arcotangente a due quadranti in GRADI, gestione (0,0)=0 e assi. Nessun uso di ATAN2 di libreria: implementazione con ATAN + casi assiali.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rY=1.0, rX=1.0 | 45.0 | Primo quadrante. |
| 2 | rY=1.0, rX=-1.0 | 135.0 | Secondo quadrante. |
| 3 | rY=-1.0, rX=-1.0 | -135.0 | Terzo quadrante. |
| 4 | rY=-1.0, rX=1.0 | -45.0 | Quarto quadrante. |
| 5 | rY=1.0, rX=0.0 | 90.0 | Asse +Y. |
| 6 | rY=-1.0, rX=0.0 | -90.0 | Asse -Y. |
| 7 | rY=0.0, rX=-1.0 | 180.0 | Asse -X (rY>=0 → π). |
| 8 | rY=0.0, rX=0.0 | 0.0 | Origine: ritorno deterministico 0. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Atan2(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F05:** PASS solo se tutti i 8 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F06 — `FUN_SP_NormAng` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rAng | LREAL | - | Angle to normalize [deg] |

**Tipo di ritorno:** `LREAL`

**Semantica:** Normalizzazione angolare in GRADI sull'intervallo (-180, +180]: il valore -180 viene mappato a +180.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rAng=190.0 | -170.0 | Wrap negativo. |
| 2 | rAng=-190.0 | 170.0 | Wrap positivo. |
| 3 | rAng=360.0 | 0.0 | Giro completo. |
| 4 | rAng=180.0 | 180.0 | Estremo superiore mantenuto. |
| 5 | rAng=-180.0 | 180.0 | Estremo inferiore mappato a +180. |
| 6 | rAng=725.0 | 5.0 | Doppio wrap (725-360-360=5). |
| 7 | rAng=-725.0 | -5.0 | Doppio wrap negativo. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_NormAng(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F06:** PASS solo se tutti i 7 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F07 — `FUN_SP_AngDiff` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rFrom | LREAL | - | Start angle a [deg] |
| rTo | LREAL | - | Target angle b [deg] |

**Tipo di ritorno:** `LREAL`

**Semantica:** Differenza angolare normalizzata `NormAng(rTo - rFrom)` in gradi — usata per la rotazione polso più corta.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rFrom=10.0, rTo=350.0 | -20.0 | Differenza corta negativa. |
| 2 | rFrom=350.0, rTo=10.0 | 20.0 | Differenza corta positiva. |
| 3 | rFrom=0.0, rTo=180.0 | 180.0 | Semicerchio. |
| 4 | rFrom=0.0, rTo=0.0 | 0.0 | Nessun movimento. |
| 5 | rFrom=-170.0, rTo=170.0 | -20.0 | Wrap sul confine ±180. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_AngDiff(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F07:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F08 — `FUN_SP_Dist2D` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rX1 | LREAL | - | First point, X |
| rY1 | LREAL | - | First point, Y |
| rX2 | LREAL | - | Second point, X |
| rY2 | LREAL | - | Second point, Y |

**Tipo di ritorno:** `LREAL`

**Semantica:** Distanza euclidea 2D — base del filtro doppioni (`GC_DUP_TOL_MM`) e della valutazione di separazione.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | (0,0) → (3,4) | 5.0 | Triangolo 3-4-5. |
| 2 | (1,1) → (1,1) | 0.0 | Stesso punto. |
| 3 | (-1,-1) → (2,3) | 5.0 | Quadranti misti. |
| 4 | (0,0) → (0.1,0) | 0.1 | Sotto soglia dup 25 mm: stesso pezzo. |
| 5 | (0,0) → (26,0) | 26.0 | Oltre soglia dup 25 mm: pezzi distinti. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Dist2D(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F08:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F09 — `FUN_SP_Lerp` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rA | LREAL | - | Start value (t = 0) |
| rB | LREAL | - | End value (t = 1) |
| rT | LREAL | - | 0.0 .. 1.0 |

**Tipo di ritorno:** `LREAL`

**Semantica:** Interpolazione lineare parametrica con `rT` saturato in [0,1] via `FUN_SP_Clamp`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rA=0.0, rB=10.0, rT=0.5 | 5.0 | Metà. |
| 2 | rA=0.0, rB=10.0, rT=0.0 | 0.0 | Inizio. |
| 3 | rA=0.0, rB=10.0, rT=1.0 | 10.0 | Fine. |
| 4 | rA=0.0, rB=10.0, rT=-0.5 | 0.0 | T saturato a 0. |
| 5 | rA=0.0, rB=10.0, rT=1.5 | 10.0 | T saturato a 1. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Lerp(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F09:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F10 — `FUN_SP_DigCh` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| iD | DINT | - | Digit value 0..9 |

**Tipo di ritorno:** `STRING(1)`

**Semantica:** Cifra decimale → carattere ASCII. Usa MID su `'0123456789'` con indice ClampI(iD+1,1,10).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | iD=0 | '0' | Prima cifra. |
| 2 | iD=9 | '9' | Ultima cifra. |
| 3 | iD=10 | '9' | Fuori range: saturato a '9'. |
| 4 | iD=-5 | '0' | Fuori range: saturato a '0'. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_DigCh(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F10:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F11 — `FUN_SP_DigVal` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sCh | STRING(1) | - | Character to classify as digit |

**Tipo di ritorno:** `SINT`

**Semantica:** Carattere → cifra (SINT). Ritorna -1 se il carattere non è una cifra decimale.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sCh='7' | 7 | Cifra valida. |
| 2 | sCh='0' | 0 | Zero. |
| 3 | sCh='A' | -1 | Non cifra. |
| 4 | sCh=' '-1 | Spazio. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_DigVal(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F11:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F12 — `FUN_SP_TokN` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(255) | - | Input line to tokenize |
| sDelim | STRING(1) | - | Single-character field delimiter |
| uiN | UINT | - | 1-based token index |

**Tipo di ritorno:** `STRING(64)`

**Semantica:** Estrae l'en-simo token da una stringa con delimitatore (1-based). Il token viene ritagliato (`Trims`). Se l'indice è oltre l'ultimo token ritorna stringa vuota.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='a,b,c', sDelim=',', uiN=2 | 'b' | Token centrale. |
| 2 | sTxt='a,b,c', sDelim=',', uiN=1 | 'a' | Primo token. |
| 3 | sTxt='a,b,c', sDelim=',', uiN=3 | 'c' | Ultimo token. |
| 4 | sTxt=' a , b ', sDelim=',', uiN=1 | 'a' | Con spazi: ritagliato. |
| 5 | sTxt='a,b', sDelim=',', uiN=5 | '' | Indice oltre la fine. |
| 6 | sTxt='abc', sDelim=',', uiN=1 | 'abc' | Nessun delimitatore. |
| 7 | sTxt='a,,c', sDelim=',', uiN=2 | '' | Token vuoto centrale. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TokN(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F12:** PASS solo se tutti i 7 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F13 — `FUN_SP_TokCnt` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(255) | - | Input line to tokenize |
| sDelim | STRING(1) | - | Single-character field delimiter |

**Tipo di ritorno:** `UINT`

**Semantica:** Conta i token (numero di delimitatori + 1). Con delimitatore vuoto ritorna 0. Con stringa vuota e delimitatore valido ritorna 1 (contatore inizializzato a 1).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='a,b,c', sDelim=',' | 3 | Tre token. |
| 2 | sTxt='abc', sDelim=',' | 1 | Un token. |
| 3 | sTxt='a,b,c,d,e', sDelim=',' | 5 | Cinque token. |
| 4 | sTxt='a,b,c', sDelim='' | 0 | Delimitatore vuoto. |
| 5 | sTxt='', sDelim=',' | 1 | Stringa vuota: 1 token vuoto (comportamento atteso del codice). |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TokCnt(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F13:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F14 — `FUN_SP_Trims` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(64) | - | String to trim |

**Tipo di ritorno:** `STRING(64)`

**Semantica:** Ritaglia spazi iniziali e finali (max 64 caratteri in ingresso).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='  ab  ' | 'ab' | Entrambi i lati. |
| 2 | sTxt='ab' | 'ab' | Nessuno spazio. |
| 3 | sTxt='    ' | '' | Solo spazi. |
| 4 | sTxt=' a b ' | 'a b' | Spazio interno mantenuto. |
| 5 | sTxt='' | '' | Vuota. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Trims(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F14:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F15 — `FUN_SP_StrToLReal` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(32) | - | Text to parse as decimal LREAL |
| rDefault | LREAL | - | Value returned when parsing fails |

**Tipo di ritorno:** `LREAL`

**Semantica:** Parser di stringa → LREAL con segno, parte frazionaria, notazione esponenziale (`e`/`E`), default su input non valido (carattere non valido → ritorna immediatamente il default). Lunghezza ammessa 1..24 dopo trim.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt=' 12.5 ', rDefault=0.0 | 12.5 | Con spazi. |
| 2 | sTxt='-3.25e2', rDefault=0.0 | -325.0 | Esponente positivo. |
| 3 | sTxt='1.5E-1', rDefault=0.0 | 0.15 | Esponente negativo. |
| 4 | sTxt='abc', rDefault=7.0 | 7.0 | Carattere non valido → default. |
| 5 | sTxt='12a3', rDefault=7.0 | 7.0 | Interruzione su carattere non valido. |
| 6 | sTxt='', rDefault=5.0 | 5.0 | Stringa vuota. |
| 7 | sTxt='+42', rDefault=0.0 | 42.0 | Segno più. |
| 8 | sTxt='0.001', rDefault=0.0 | 0.001 | Piccola frazione. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_StrToLReal(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F15:** PASS solo se tutti i 8 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F16 — `FUN_SP_StrToUi` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(16) | - | Digits-only text to convert (UINT) |
| uiDefault | UINT | - | Value returned when parsing fails |

**Tipo di ritorno:** `UINT`

**Semantica:** Stringa → UINT (solo cifre, max 9 caratteri). Default se non valido.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='123', uiDefault=0 | 123 | Normale. |
| 2 | sTxt='0', uiDefault=9 | 0 | Zero distinto dal default. |
| 3 | sTxt='12a', uiDefault=9 | 9 | Default su non-numerico. |
| 4 | sTxt='', uiDefault=7 | 7 | Vuota. |
| 5 | sTxt='123456789', uiDefault=0 | 123456789 | 9 cifre ammesse. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_StrToUi(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F16:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F17 — `FUN_SP_StrToUd` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(16) | - | Digits-only text to convert (UDINT) |
| udiDefault | UDINT | - | Value returned when parsing fails |

**Tipo di ritorno:** `UDINT`

**Semantica:** Stringa → UDINT (solo cifre, max 10 caratteri). Default se non valido.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='4294967295', udiDefault=0 | 4294967295 | Massimo UDINT. |
| 2 | sTxt='40000', udiDefault=0 | 40000 | Oltre UINT: ammesso (UDINT). |
| 3 | sTxt='12x', udiDefault=3 | 3 | Default su non-numerico. |
| 4 | sTxt='', udiDefault=4 | 4 | Vuota. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_StrToUd(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F17:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F18 — `FUN_SP_UiToStr` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| uiVal | UINT | - | Value to format as decimal text |

**Tipo di ritorno:** `STRING(16)`

**Semantica:** UINT → stringa decimale senza zeri iniziali.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | uiVal=0 | '0' | Zero. |
| 2 | uiVal=123 | '123' | Normale. |
| 3 | uiVal=65535 | '65535' | Massimo UINT. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_UiToStr(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F18:** PASS solo se tutti i 3 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F19 — `FUN_SP_UdToStr` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| udiVal | UDINT | - | 32-bit value to format as decimal text |

**Tipo di ritorno:** `STRING(16)`

**Semantica:** UDINT → stringa decimale.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | udiVal=0 | '0' | Zero. |
| 2 | udiVal=4000000000 | '4000000000' | Oltre UINT. |
| 3 | udiVal=98765 | '98765' | Normale. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_UdToStr(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F19:** PASS solo se tutti i 3 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F20 — `FUN_SP_LRealToStr` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rVal | LREAL | - | Value to format |
| iDec | SINT | - | number of decimal digits, 0..6 |

**Tipo di ritorno:** `STRING(24)`

**Semantica:** LREAL → stringa con numero fisso di decimali (0..6, saturato), arrotondamento all'ultima cifra e riporto sulla parte intera.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rVal=12.345, iDec=2 | '12.35' | Arrotondamento (0.345→0.35). |
| 2 | rVal=3.14159, iDec=3 | '3.142' | Arrotondamento. |
| 3 | rVal=-0.5, iDec=1 | '-0.5' | Negativo. |
| 4 | rVal=9.999, iDec=2 | '10.00' | Riporto su parte intera. |
| 5 | rVal=5.0, iDec=0 | '5' | Zero decimali. |
| 6 | rVal=1.23, iDec=9 | '1.230000' | iDec saturato a 6. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_LRealToStr(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F20:** PASS solo se tutti i 6 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F21 — `FUN_SP_VisAppend` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sBuf | STRING(240) | - | Current accumulation |
| sChunk | STRING(255) | - | Data to append |

**Tipo di ritorno:** `STRING(240)`

**Semantica:** Accoda frammenti ASCII in un buffer di 240 caratteri. Se il totale supera 240, conserva gli ultimi 200 caratteri (sliding window per il log visuale).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sBuf='abc', sChunk='def' | 'abcdef' | Accodamento semplice. |
| 2 | sBuf='', sChunk='x' | 'x' | Buffer vuoto. |
| 3 | sBuf=240×'a', sChunk='b' | 200 caratteri: gli ultimi 199 'a' + 'b' | Overflow: finestra 200. |
| 4 | sBuf=239×'a', sChunk='b' | 240 caratteri: 239 'a' + 'b' | Esattamente al limite. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_VisAppend(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F21:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F22 — `FUN_SP_StrSum` (01_Common/FUN_SP_Parse.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| sTxt | STRING(120) | - | Text whose additive checksum is computed |

**Tipo di ritorno:** `UDINT`

**Semantica:** Checksum additivo su stringa: per ogni carattere nella tabella `'0123456789A-Za-z.-_:=,;/[] '` somma (posizione 1-based + 31×indice 1-based); caratteri fuori tabella sommano 127. Usato da `SP_RetainMgr.ChkSum`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | sTxt='A' | 42 | Pos('A')=11 + 31×1 = 42. |
| 2 | sTxt='AB' | 116 | (11+31) + (12+62) = 116. |
| 3 | sTxt='' | 0 | Stringa vuota. |
| 4 | sTxt='0' | 32 | Pos('0')=1 + 31×1 = 32. |
| 5 | sTxt con carattere non in tabella (es. '\t') | 127 per quel carattere | Verificare somma parziale. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_StrSum(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F22:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F23 — `FUN_SP_ByteCh` (01_Common/FUN_SP_ByteCh.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| byVal | BYTE | - | Byte code received from the socket (ASCII expected) |

**Tipo di ritorno:** `STRING(1)`

**Semantica:** BYTE -> carattere ASCII stampabile: GC_ASCII95[byVal-31] se 32..126, altrimenti ".".

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | byVal=65 (A) | 'A' | Lettera maiuscola. |
| 2 | byVal=32 (spazio) | 'spazio' | Primo carattere della tabella. |
| 3 | byVal=126 | ~ | Ultimo carattere della tabella. |
| 4 | byVal=10 (LF) | '.' | Non stampabile -> punto. |
| 5 | byVal=0 | '.' | Non stampabile -> punto. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_ByteCh(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F23:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F24 — `FUN_SP_RtcToStr` (01_Common/FUN_SP_RtcToStr.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stRtc | Yt_YA_RTC_Struct | - | RTC snapshot to format (Yaskawa Yt_YA_RTC_Struct, INT fields) |

**Tipo di ritorno:** `STRING(23)`

**Semantica:** Struttura RTC → stringa `YYYY-MM-DD hh:mm:ss.mmm` (23 caratteri). Campi fuori range vengono azzerati (clamp deterministico); Anno≤0 → 0000.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | Year=2026, Month=10, Day=13, Hour=9, Min=5, Sec=3, mSec=7 | '2026-10-13 09:05:03.007' | Formato standard. |
| 2 | Year=0, Month=0, Day=0, Hour=0, Min=0, Sec=0, mSec=0 | '0000-00-00 00:00:00.000' | RTC non inizializzato. |
| 3 | Month=13 → atteso 00 | "…-00-…" | Mese fuori range azzerato. |
| 4 | Hour=24 → atteso 00 | "… 00:…" | Ora fuori range azzerata. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_RtcToStr(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F24:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F25 — `FUN_SP_TickToRtc` (01_Common/FUN_SP_TickToRtc.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| udiMs | UDINT | - | Monotonic milliseconds since boot (GVL_SP_Rtc.g_udiTickMs) |

**Tipo di ritorno:** `Yt_YA_RTC_Struct`

**Semantica:** Millisecondi dall'epoch Unix (1970-01-01 00:00:00) → struttura RTC (algoritmo diecimaleera/civil-from-days).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | udiMs=0 | 1970-01-01 00:00:00.000 | Epoch. |
| 2 | udiMs=86400000 | 1970-01-02 00:00:00.000 | +1 giorno. |
| 3 | udiMs=1704067200000 (verificare troncamento UDINT!) | — | NOTA: UDINT max ≈ 4.29e9 ms ≈ 49.7 giorni: il test verifica il comportamento di overflow atteso (wrap modulo 2^32) e va documentato; per timestamp reali usare `GVL_SP_Rtc.stRtc` aggiornato dal runtime. |
| 4 | udiMs=3661000 | 1970-01-01 01:01:01.000 | Ora:min:sec = 1:01:01. |
| 5 | udiMs=1500 | 1970-01-01 00:00:01.500 | mSec=500. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TickToRtc(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F25:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F26 — `FUN_SP_ErrorText` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| eRc | ET_SP_RetCode | - | Return code to translate |

**Tipo di ritorno:** `STRING(40)`

**Semantica:** Mappa `ET_SP_RetCode` → testo inglese dell'errore (per log e HMI).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | ET_SP_RetCode#Done | 'OK' | Successo. |
| 2 | ET_SP_RetCode#ErrParam | 'Invalid parameter' | Parametro. |
| 3 | ET_SP_RetCode#ErrFull | 'Buffer full' | Buffer. |
| 4 | ET_SP_RetCode#ErrCom | 'Communication error' | Comunicazione. |
| 5 | Valore enum non gestito (se presente) | stringa ELSE dedicata | Verificare ramo ELSE. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_ErrorText(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F26:** PASS solo se tutti i 5 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F27 — `FUN_SP_SrcText` (01_Common/FUN_SP_Utils.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| eSrc | ET_SP_LogSource | - | Module selector |

**Tipo di ritorno:** `STRING(12)`

**Semantica:** Mappa `ET_SP_LogSource` → tag sorgente log (max 12 caratteri).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | ET_SP_LogSource#System | 'SYSTEM' | Sistema. |
| 2 | ET_SP_LogSource#Camera | 'CAMERA' | Visione. |
| 3 | ET_SP_LogSource#Simulation | 'SIM' | Simulazione. |
| 4 | ET_SP_LogSource#Persist | 'PERSIST' | Persistenza. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_SrcText(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F27:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F28 — `FUN_SP_TrfX` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform to apply |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** Trasformazione diretta (similitudine 2D): `X = rDx + rScale·(cosθ·rX − sinθ·rY)` con θ=`rRot` in gradi.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T={dx=100, dy=200, scale=2, rot=90}, rX=1, rY=0 | 100.0 | cos90=0, sin90=1 → 100. |
| 2 | T come sopra, rX=0, rY=1 | 98.0 | −2·1+100 = 98. |
| 3 | T={dx=0,dy=0,scale=1,rot=0}, rX=5, rY=5 | 5.0 | Identità. |
| 4 | T={dx=0,dy=0,scale=1,rot=180}, rX=1, rY=0 | -1.0 | Rotazione 180°. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TrfX(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F28:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F29 — `FUN_SP_TrfY` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform to apply |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** `Y = rDy + rScale·(sinθ·rX + cosθ·rY)`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T={dx=100, dy=200, scale=2, rot=90}, rX=1, rY=0 | 202.0 | 2·1+200. |
| 2 | T come sopra, rX=0, rY=1 | 200.0 | cos90=0. |
| 3 | T identità, (5,5) | 5.0 | Identità. |
| 4 | Round-trip con UT-F28/30/31: Trf→InvTrf | (rX, rY) originali | Errore < 1e-9. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TrfY(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F29:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F30 — `FUN_SP_InvTrfX` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform whose inverse is applied |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** Trasformazione inversa: `x = (cosθ·px + sinθ·py)/scale` con `p = (rX−rDx, rY−rDy)`. Scale≈0 (<1e-9) → ritorna 0.0.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T={dx=100,dy=200,scale=2,rot=90}, rX=100, rY=202 | 1.0 | Inverso del caso UT-F28/1. |
| 2 | T come sopra, rX=98, rY=200 | 0.0 | Inverso del caso 2. |
| 3 | T con scale=0 | 0.0 | Protezione divisione per zero. |
| 4 | Round-trip Trf→Inv su 10 punti casuali | punto originale | Max errore 1e-9. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_InvTrfX(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F30:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F31 — `FUN_SP_InvTrfY` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform whose inverse is applied |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** `y = (−sinθ·px + cosθ·py)/scale`. Stesse protezioni di InvTrfX.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T={dx=100,dy=200,scale=2,rot=90}, rX=100, rY=202 | 0.0 | Inverso del caso 1. |
| 2 | T come sopra, rX=98, rY=200 | 1.0 | Inverso del caso 2. |
| 3 | T con scale=0 | 0.0 | Protezione divisione per zero. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_InvTrfY(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F31:** PASS solo se tutti i 3 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F32 — `FUN_SP_TrfTh` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform to apply |
| rTh | LREAL | - | Angle to transform [deg] |

**Tipo di ritorno:** `LREAL`

**Semantica:** Orientamento diretto: `NormAng(rRot + rTh)`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T.rRot=90, rTh=10 | 100.0 | Somma. |
| 2 | T.rRot=90, rTh=100 | -170.0 | Wrap oltre 180. |
| 3 | T.rRot=-30, rTh=-160 | -190 → 170.0 | Wrap negativo. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_TrfTh(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F32:** PASS solo se tutti i 3 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F33 — `FUN_SP_InvTrfTh` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stT | ST_SP_Transf2D | - | Transform whose inverse is applied |
| rTh | LREAL | - | Angle to transform [deg] |

**Tipo di ritorno:** `LREAL`

**Semantica:** Orientamento inverso: `NormAng(rTh − rRot)`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | T.rRot=90, rTh=100 | 10.0 | Inverso di UT-F32/1. |
| 2 | T.rRot=90, rTh=-170 | -260 → 100.0 | Wrap. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_InvTrfTh(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F33:** PASS solo se tutti i 2 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F34 — `FUN_SP_RotX` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rAng | LREAL | - | Rotation angle about origin [deg] |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** Rotazione pura X: `cosθ·rX − sinθ·rY` (θ in gradi). Usata per la proiezione dei cup offset nel TCP.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rAng=90, rX=1, rY=0 | 0.0 | cos90=0. |
| 2 | rAng=90, rX=0, rY=1 | -1.0 | −sin90. |
| 3 | rAng=0, rX=3, rY=4 | 3.0 | Identità. |
| 4 | rAng=180, rX=2, rY=0 | -2.0 | Rotazione piatta. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_RotX(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F34:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F35 — `FUN_SP_RotY` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| rAng | LREAL | - | Rotation angle about origin [deg] |
| rX | LREAL | - | Point X to rotate |
| rY | LREAL | - | Point Y to rotate |

**Tipo di ritorno:** `LREAL`

**Semantica:** Rotazione pura Y: `sinθ·rX + cosθ·rY`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | rAng=90, rX=1, rY=0 | 1.0 | sin90. |
| 2 | rAng=90, rX=0, rY=1 | 0.0 | cos90=0. |
| 3 | rAng=0, rX=3, rY=4 | 4.0 | Identità. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_RotY(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F35:** PASS solo se tutti i 3 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F36 — `FUN_SP_Pose3InWin` (02_Geometry/FUN_SP_Geometry.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| p3 | ST_SP_Pose3D | - | Pose to test (X/Y used, Z ignored) |
| rXmin | LREAL | - | Window lower X bound |
| rXmax | LREAL | - | Window upper X bound |
| rYmin | LREAL | - | Window lower Y bound |
| rYmax | LREAL | - | Window upper Y bound |

**Tipo di ritorno:** `BOOL`

**Semantica:** Verifica appartenenza della coordinata X/Y di una posa al rettangolo [Xmin..Xmax]×[Ymin..Ymax] (estremi inclusi). Il campo `rTh` è ignorato.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | p3=(5,5,0), finestra (0..10)×(0..10) | TRUE | Interno. |
| 2 | p3=(0,0,0), finestra (0..10)×(0..10) | TRUE | Su vertice (estremi inclusi). |
| 3 | p3=(10.001,5,0), finestra (0..10)×(0..10) | FALSE | Appena fuori X. |
| 4 | p3=(5,-0.001,0), finestra (0..10)×(0..10) | FALSE | Appena fuori Y. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_Pose3InWin(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F36:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F37 — `FUN_SP_FitYaw` (13_MultiGrip/FUN_SP_ClusterMath.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| astP | ARRAY[1..4] OF ST_SP_Pose3D | - | Member item poses (world) 1..GC_CUPS |
| uiN | UINT | - | Number of valid members 1..GC_CUPS |

**Tipo di ritorno:** `LREAL`

**Semantica:** Yaw medio di un cluster via media vettoriale: `Atan2(Σ sin θi, Σ cos θi)` (risultato in gradi).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | θ = [10, 20, 30], uiN=3 | 20.0 | Media vettoriale = 20°. |
| 2 | θ = [0, 0, 0], uiN=2 | 0.0 | Allineati a zero. |
| 3 | θ = [0, 180], uiN=2 | Atan2(0, 0)=0.0 | Vettori opposti: risultato deterministico 0. |
| 4 | uiN=0 | 0.0 | Protezione ingresso. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_FitYaw(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F37:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F38 — `FUN_SP_ClusterResidual` (13_MultiGrip/FUN_SP_ClusterMath.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| astP | ARRAY[1..4] OF ST_SP_Pose3D | - | Member item poses (world, XY used) 1..GC_CUPS |
| astC | ARRAY[1..4] OF ST_SP_Point3D | - | Cup offsets in the tool frame (XY used) 1..GC_CUPS |
| stTcp | ST_SP_Pose3D | - | Candidate synchronized TCP pose |
| uiN | UINT | - | Number of valid members/cups 1..GC_CUPS |

**Tipo di ritorno:** `LREAL`

**Semantica:** Errore massimo (residuo) fra le posizioni reali dei pezzi e le posizioni dei cup proiettati dalla posa TCP: `max|P_item − (TCP + R(θtcp)·Cup)|`.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | TCP=(0,0,0°), cup=(10,0,0), item=(10,0) | 0.0 | Cluster perfetto. |
| 2 | TCP=(0,0,0°), cup=(10,0,0), item=(13,0) | 3.0 | Errore 3 mm su X. |
| 3 | TCP=(0,0,90°), cup=(10,0,0), item=(0,10) | 0.0 | Cup ruotato dal TCP: proiezione corretta. |
| 4 | uiN=0 | 0.0 | Protezione ingresso. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_ClusterResidual(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F38:** PASS solo se tutti i 4 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F39 — `FUN_SP_CamPreset` (04_Vision/FUN_SP_CamPreset.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stIn | ST_SP_VisionCfg | - | Current configuration (fill-if-empty) |
| iModel | SINT | - | Model selector, see header |

**Tipo di ritorno:** `ST_SP_VisionCfg`

**Semantica:** Preset di configurazione camera per modello: −1 Cognex (porta 5000), +1 Keyence (8888), +2 GenericTCP (10001), +3 Simulated. Valori di default: tTimeout=800 ms, tDelay=40 ms, tInterval=200 ms, uiMaxItems=GC_VIS_MAX, rMinScore=0.5, bThInRad=FALSE, bUsed=TRUE.

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | iModel=-1, stIn con uiPort=0 | eDrv=Cognex, uiPort=5000 | Preset Cognex. |
| 2 | iModel=1, uiPort=0 | eDrv=Keyence, uiPort=8888 | Preset Keyence. |
| 3 | iModel=2, uiPort=0 | eDrv=GenericTCP, uiPort=10001 | Preset generico. |
| 4 | iModel=3 | eDrv=Simulated | Simulatore. |
| 5 | iModel=0 (o altro) | stIn invariato, uscita immediata | Modello sconosciuto. |
| 6 | Qualsiasi modello valido, tTimeout=T#0ms | tTimeout=T#800ms | Default timeout. |
| 7 | Qualsiasi modello valido, tDelay=T#0ms | tDelay=T#40ms | Default trigger delay. |
| 8 | Qualsiasi modello valido, rMinScore=0.0 | rMinScore=0.5 | Default score. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_CamPreset(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F39:** PASS solo se tutti i 8 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

### UT-F40 — `FUN_SP_RobCfgDefault` (12_Application/FUN_SP_RobCfgDefault.st)

**Firma (VAR_IN esatti):**

| Parametro | Tipo | Default | Descrizione |
|---|---|---|---|
| stIn | ST_SP_RobCfg | - | Current configuration (fill-if-empty) |
| iRob | SINT | - | Robot index 1..GC_ROBOTS |

**Tipo di ritorno:** `ST_SP_RobCfg`

**Semantica:** Configurazione robot di default: se `stIn.uiNumTools` e gia valido (1..GC_TOOLS) restituisce invariato; altrimenti applica il profilo di fabbrica (1 attrezzo `Gripper1` a 2 ventose, offset cup ±30 mm, tGrip 150 ms, tRelease 100 ms, rAdvance 40 mm, rMaxWeight 500 g, `bUsed=TRUE`, sName `RobotN`).

**Casi di test:**

| Caso | Stimolo (scrivere in Watch) | Risultato atteso | Note |
|---|---|---|---|
| 1 | stIn.uiNumTools=0, iRob=3 | uiNumTools=1, sName=`Robot3`, astTools[1].sName=`Gripper1`, astTools[1].uiCups=2 | Profilo di fabbrica applicato. |
| 2 | stIn.uiNumTools=2 (valido) | stIn invariato | Configurazione utente preservata. |
| 3 | stIn.uiNumTools=99 (> GC_TOOLS=4) | Profilo di fabbrica | Valore non valido: default. |
| 4 | Default: astTools[1].astCups[1].rX | -30.0 | Cup 1 a −30 mm. |
| 5 | Default: astTools[1].astCups[2].rX | +30.0 | Cup 2 a +30 mm. |
| 6 | Default: astTools[1].tGrip / tRelease | T#150ms / T#100ms | Tempi valvola. |
| 7 | Default: astTools[1].bSuction | TRUE | Ventosa (non pinza). |
| 8 | Default: uiGroup | = iRob | Gruppo di moto = indice robot. |

**Procedura:**

1. Aprire `PRG_UT_Scratch`; dichiarare le variabili di stimolo con i tipi della firma qui sopra.
2. Impostare gli input del Caso 1.
3. Eseguire `x := FUN_SP_RobCfgDefault(<input>);` e leggere `x` su Watch.
4. Confrontare con il risultato atteso (tolleranza ±0.001 su LREAL, esatto su stringhe/interi/bool).
5. Ripetere i passi 2-4 per tutti i casi della tabella.

**Criterio UT-F40:** PASS solo se tutti i 8 casi corrispondono.

**Casi limite supplementari:**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| SL-1 | Chiamare la funzione due volte consecutive con gli stessi input. | Stesso risultato (purezza: nessun stato interno). |
| SL-2 | Input al limite dello 0 (o stringa vuota). | Risultato deterministico, nessun crash. |
| SL-3 | Input al massimo del tipo (es. LREAL grande, STRING piena). | Nessun overflow di runtime; saturazione o gestione esplicita. |
| SL-4 | Controllare che il risultato non dipenda dal task chiamante (Fast/Main/Svc). | Identico da qualunque task. |


---

## Sezione 2 — Unit Test dei DUT/TYPE e dei GVL (UT-D01 .. UT-D81, UT-G01 .. UT-G10)

I test sui tipi di dati verificano: enumerati con valori attesi, campi delle strutture con inizializzazioni di default, e la corretta visibilità/inizializzazione dei GVL. Non richiedono esecuzione: sono verifiche di compilazione + ispezione online (tranne alcune verifiche dinamiche indicate).

---

### UT-D01 — TYPE `ET_SP_RetCode` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Done | 0 |
| Busy | 1 |
| Idle | 2 |
| ErrParam | 10 |
| ErrState | 11 |
| ErrFull | 12 |
| ErrEmpty | 13 |
| ErrNotFound | 14 |
| ErrCom | 15 |
| ErrIo | 16 |
| ErrBusy | 17 |
| ErrRange | 18 |
| NotImpl | 99 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_RetCode;`.
2. Assegnare ogni letterale (es. `x := ET_SP_RetCode#Done;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D01:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D02 — TYPE `ET_SP_LogLevel` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Debug | 0 |
| Info | 1 |
| Warn | 2 |
| Error | 3 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_LogLevel;`.
2. Assegnare ogni letterale (es. `x := ET_SP_LogLevel#Debug;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D02:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D03 — TYPE `ET_SP_LogSource` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| System | 0 |
| Robot | 1 |
| Feed | 2 |
| Conveyor | 3 |
| Camera | 4 |
| Balancer | 5 |
| Batch | 6 |
| Persist | 7 |
| Simulation | 8 |
| User | 9 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_LogSource;`.
2. Assegnare ogni letterale (es. `x := ET_SP_LogSource#System;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D03:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D04 — TYPE `ET_SP_SysState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Init | 0 |
| Standby | 10 |
| Starting | 20 |
| Running | 30 |
| Pausing | 40 |
| Paused | 50 |
| Resuming | 60 |
| Stopping | 70 |
| Stopped | 80 |
| Recovering | 90 |
| Fault | 100 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_SysState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_SysState#Init;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D04:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D05 — TYPE `ET_SP_AckState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Inactive | 0 |
| Active | 1 |
| Acked | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_AckState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_AckState#Inactive;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D05:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D06 — TYPE `ET_SP_ItemState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Free | 0 |
| Tracked | 10 |
| Reserved | 20 |
| Picked | 30 |
| Held | 40 |
| Placed | 50 |
| Lost | 60 |
| TimedOut | 70 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_ItemState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_ItemState#Free;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D06:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D07 — TYPE `ET_SP_RobState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Init | 0 |
| Homing | 10 |
| Ready | 20 |
| WaitJob | 30 |
| PlanPick | 40 |
| MoveApp | 50 |
| TrackPick | 60 |
| Grip | 70 |
| GripEval | 71 |
| Depart | 80 |
| PlanPlace | 90 |
| MovePlace | 100 |
| Place | 110 |
| Release | 120 |
| Retreat | 130 |
| Verify | 140 |
| Paused | 150 |
| Trial | 160 |
| Fault | 170 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_RobState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_RobState#Init;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D07:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D08 — TYPE `ET_SP_Precision` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Exact | 0 |
| ZoneTight | 1 |
| ZoneWide | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_Precision;`.
2. Assegnare ogni letterale (es. `x := ET_SP_Precision#Exact;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D08:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D09 — TYPE `ET_SP_MatchMode` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Matched | 0 |
| Unmatched | 1 |
| Mixed | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_MatchMode;`.
2. Assegnare ogni letterale (es. `x := ET_SP_MatchMode#Matched;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D09:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D10 — TYPE `ET_SP_ShareStrategy` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Organic | 0 |
| Greedy | 1 |
| Balanced | 2 |
| Manual | 3 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_ShareStrategy;`.
2. Assegnare ogni letterale (es. `x := ET_SP_ShareStrategy#Organic;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D10:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D11 — TYPE `ET_SP_GripMode` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Sync | 0 |
| Partial | 1 |
| Async | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_GripMode;`.
2. Assegnare ogni letterale (es. `x := ET_SP_GripMode#Sync;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D11:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D12 — TYPE `ET_SP_JobKind` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Pick | 0 |
| Place | 1 |
| PickPlace | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_JobKind;`.
2. Assegnare ogni letterale (es. `x := ET_SP_JobKind#Pick;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D12:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D13 — TYPE `ET_SP_BatchState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Idle | 0 |
| Running | 10 |
| Paused | 20 |
| Done | 30 |
| Aborted | 40 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_BatchState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_BatchState#Idle;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D13:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D14 — TYPE `ET_SP_PattTrig` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Distance | 0 |
| Sensor | 1 |
| BatchStart | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_PattTrig;`.
2. Assegnare ogni letterale (es. `x := ET_SP_PattTrig#Distance;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D14:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D15 — TYPE `ET_SP_VisionDrv` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Cognex | 0 |
| Keyence | 1 |
| GenericTCP | 2 |
| Simulated | 3 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_VisionDrv;`.
2. Assegnare ogni letterale (es. `x := ET_SP_VisionDrv#Cognex;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D15:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D16 — TYPE `ET_SP_VisionState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Offline | 0 |
| Connecting | 10 |
| Online | 20 |
| Triggered | 30 |
| Ready | 50 |
| Fault | 90 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_VisionState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_VisionState#Offline;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D16:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D17 — TYPE `ET_SP_TrigMode` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Distance | 0 |
| External | 1 |
| Interval | 2 |
| Manual | 3 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_TrigMode;`.
2. Assegnare ogni letterale (es. `x := ET_SP_TrigMode#Distance;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D17:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D18 — TYPE `ET_SP_ConvDriveMode` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Analog | 0 |
| ServoAxis | 1 |
| External | 2 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_ConvDriveMode;`.
2. Assegnare ogni letterale (es. `x := ET_SP_ConvDriveMode#Analog;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D18:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D19 — TYPE `ET_SP_SocketState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Closed | 0 |
| Connecting | 10 |
| Connected | 20 |
| Fault | 90 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_SocketState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_SocketState#Closed;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D19:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D20 — TYPE `ET_SP_FileState` (01_Common/DUT_SP_Enums_Common.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| Closed | 0 |
| Opening | 10 |
| Open | 20 |
| Working | 30 |
| Closing | 40 |
| Fault | 90 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_FileState;`.
2. Assegnare ogni letterale (es. `x := ET_SP_FileState#Closed;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D20:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D21 — TYPE `ST_SP_Version` (01_Common/DUT_SP_Structs_Common.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| sName | STRING(32) | - | Library name |
| uiMajor | UINT | - | Major version |
| uiMinor | UINT | - | Minor version |
| uiBuild | UINT | - | Build number |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Version;` e azzerarla (`st := ST_SP_Version#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D21:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D22 — TYPE `ST_SP_LogEntry` (01_Common/DUT_SP_Structs_Common.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| udiSeq | UDINT | - | Monotonic sequence number |
| stTime | Yt_YA_RTC_Struct | - | Wall clock stamp (Yaskawa RTC, v1.8.0) |
| eLevel | ET_SP_LogLevel | - | Severity |
| eSrc | ET_SP_LogSource | - | Originating module |
| uiCode | UINT | - | Optional module specific code |
| sText | STRING(120) | - | Message text, English |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_LogEntry;` e azzerarla (`st := ST_SP_LogEntry#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D22:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D23 — TYPE `ST_SP_Alarm` (01_Common/DUT_SP_Structs_Common.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| uiId | UINT | - | Unique alarm identifier (>0) |
| eState | ET_SP_AckState | - | Active / Acked lifecycle |
| eLevel | ET_SP_LogLevel | - | Severity of the alarm |
| eSrc | ET_SP_LogSource | - | Originating module |
| sText | STRING(80) | - | Alarm text, English |
| stRaised | Yt_YA_RTC_Struct | - | Wall clock of raise (Yaskawa RTC) |
| stCleared | Yt_YA_RTC_Struct | - | Wall clock of clear (nil when active) |
| udiCnt | UDINT | - | Number of occurrences |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Alarm;` e azzerarla (`st := ST_SP_Alarm#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D23:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D24 — TYPE `ST_SP_Counters` (01_Common/DUT_SP_Structs_Common.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| udiPickOk | UDINT | - | Successful picks |
| udiPickNg | UDINT | - | Failed picks (verification NG) |
| udiPlaceOk | UDINT | - | Successful placements |
| udiPlaceNg | UDINT | - | Failed placements |
| udiCycles | UDINT | - | Completed pick/place cycles |
| udiAlarms | UDINT | - | Raised alarms |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Counters;` e azzerarla (`st := ST_SP_Counters#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D24:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D25 — TYPE `ST_SP_RetCodeMsg` (01_Common/DUT_SP_Structs_Common.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eRc | ET_SP_RetCode | - | Return code |
| uiCode | UINT | - | Extended module code, 0 = none |
| sText | STRING(80) | - | Human readable message |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RetCodeMsg;` e azzerarla (`st := ST_SP_RetCodeMsg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D25:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D26 — TYPE `ST_SP_Point2D` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rX | LREAL | - | X coordinate [mm] |
| rY | LREAL | - | Y coordinate [mm] |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Point2D;` e azzerarla (`st := ST_SP_Point2D#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D26:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D27 — TYPE `ST_SP_Pose2D` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rX | LREAL | - | X position [mm] |
| rY | LREAL | - | Y position [mm] |
| rTh | LREAL | - | Yaw angle [deg] |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Pose2D;` e azzerarla (`st := ST_SP_Pose2D#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D27:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D28 — TYPE `ST_SP_Point3D` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rX | LREAL | - | X position [mm] |
| rY | LREAL | - | Y position [mm] |
| rZ | LREAL | - | Z position (height) [mm] |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Point3D;` e azzerarla (`st := ST_SP_Point3D#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D28:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D29 — TYPE `ST_SP_Pose3D` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rX | LREAL | - | X position [mm] |
| rY | LREAL | - | Y position [mm] |
| rZ | LREAL | - | Z position (height) [mm] |
| rTh | LREAL | - | C rotation around vertical axis [deg] |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Pose3D;` e azzerarla (`st := ST_SP_Pose3D#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D29:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D30 — TYPE `ST_SP_Transf2D` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rDx | LREAL | - | Translation X (parent frame) [mm] |
| rDy | LREAL | - | Translation Y (parent frame) [mm] |
| rRot | LREAL | - | Rotation child->parent [deg] |
| rScale | LREAL | - | Uniform scale child->parent [u_child/u_parent] |
| bValid | BOOL | - | TRUE after successful calibration |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Transf2D;` e azzerarla (`st := ST_SP_Transf2D#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D30:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D31 — TYPE `ST_SP_CalibStat` (02_Geometry/DUT_SP_Geometry.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iPairs | SINT | - | Number of registered point pairs |
| rRms | LREAL | - | RMS residual of the fit [user unit] |
| bValid | BOOL | - | TRUE when a valid transform is available |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_CalibStat;` e azzerarla (`st := ST_SP_CalibStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D31:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D32 — TYPE `ST_SP_ConvCfg` (03_Conveyor/DUT_SP_ConveyorTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Feed enabled in the system layout |
| sName | STRING(16) | - | Human readable conveyor name |
| rEncScale | LREAL | - | User units per encoder unit [mm/cnt] |
| iDir | SINT | - | Belt direction vs encoder: +1 / -1 |
| rMaxSpeed | LREAL | - | Max belt speed [mm/s] |
| rWinStart | LREAL | - | Distance pick-line -> window start, upstream [mm] |
| rWinLen | LREAL | - | Tracking window length [mm] |
| rSlowAhead | LREAL | - | Slow-down threshold ahead of pick line [mm] |
| rStopAhead | LREAL | - | Stop threshold ahead of pick line [mm] |
| rSlowFactor | LREAL | - | Speed factor inside slow region [0.05..1] |
| eDrive | ET_SP_ConvDriveMode | - | Drive technology |
| uiAnaCh | UINT | - | Analog channel index (GVL_SP_Io.grConvDrive) |
| rAccel | LREAL | - | Belt acceleration [mm/s2] (servo mode) |
| bStopIdle | BOOL | - | Stop belt when no items are tracked |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ConvCfg;` e azzerarla (`st := ST_SP_ConvCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D32:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D33 — TYPE `ST_SP_ConvStat` (03_Conveyor/DUT_SP_ConveyorTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rPos | LREAL | - | Belt position [mm, monotonic encoder] |
| rSpeed | LREAL | - | Signed belt speed [mm/s] |
| bActive | BOOL | - | Belt enabled and position valid |
| bInSlow | BOOL | - | Slow region active |
| bInStop | BOOL | - | Stop region active |
| rReqFactor | LREAL | - | Requested speed factor [0..1] |
| udiTrigCnt | UDINT | - | Distance trigger counter (camera support) |
| bSim | BOOL | - | TRUE = simulated conveyor |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ConvStat;` e azzerarla (`st := ST_SP_ConvStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D33:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D34 — TYPE `ST_SP_VisionItem` (04_Vision/DUT_SP_VisionTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| udiId | UDINT | - | Globally unique item id (system counter) |
| uiTypeId | UINT | - | Product type 1..GC_TYPES, 0 = unknown |
| p2 | ST_SP_Pose2D | - | Pose in the producer frame (camera or feed) |
| rScore | LREAL | - | Vision match score [0..1] |
| rWeight | LREAL | - | Part weight [g], 0 = unknown |
| rBeltPos | LREAL | - | Belt encoder coordinate at capture [mm] |
| bTarget | BOOL | - | TRUE = placement target, FALSE = product |
| bValid | BOOL | - | Record validity |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_VisionItem;` e azzerarla (`st := ST_SP_VisionItem#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D34:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D35 — TYPE `ST_SP_CamFeedMap` (04_Vision/DUT_SP_VisionTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iFeed | SINT | - | Linked feed 1..GC_FEEDS, 0 = unused |
| rYmin | LREAL | - | Region lower bound (camera Y, along belt) |
| rYmax | LREAL | - | Region upper bound (camera Y, along belt) |
| rTrigDist | LREAL | - | Base trigger distance for this feed [mm] |
| rRefSpeed | LREAL | - | Reference belt speed for auto-scaling [mm/s] |
| rLastTrig | LREAL | - | Belt position at last trigger (runtime) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_CamFeedMap;` e azzerarla (`st := ST_SP_CamFeedMap#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D35:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D36 — TYPE `ST_SP_VisionCfg` (04_Vision/DUT_SP_VisionTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Camera enabled |
| sName | STRING(16) | - | Human readable camera name |
| eDrv | ET_SP_VisionDrv | - | Selected driver |
| sIp | STRING(16) | - | Camera IP address |
| uiPort | UINT | - | Camera TCP port |
| tTimeout | TIME | - | Response timeout |
| tDelay | TIME | - | Delayed acquisition time after trigger |
| tInterval | TIME | - | Periodic trigger interval (Interval mode) |
| eTrig | ET_SP_TrigMode | - | Trigger policy |
| uiMaxItems | UINT | - | Max items parsed per image |
| sTrigStr | STRING(32) | - | Trigger command (Cognex/Keyence/Generic) |
| sEndTok | STRING(8) | - | Response end token, '' = idle-timeout based |
| sSendFmt | STRING(64) | - | Generic driver send template, {SEQ} macro |
| sDelim | STRING(1) | - | Result token delimiter |
| uiIdxType | UINT | - | 1-based token index: type |
| uiIdxX | UINT | - | 1-based token index: X |
| uiIdxY | UINT | - | 1-based token index: Y |
| uiIdxTh | UINT | - | 1-based token index: theta |
| uiIdxScore | UINT | - | 1-based token index: score |
| bThInRad | BOOL | - | TRUE = theta from vision in radians (converted to deg); FALSE = degrees |
| rMinScore | LREAL | - | Minimum accepted match score [0..1] |
| astMap | ARRAY[1..8] OF ST_SP_CamFeedMap | - | Feed region table 1..GC_FEEDS |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_VisionCfg;` e azzerarla (`st := ST_SP_VisionCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D36:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D37 — TYPE `ST_SP_VisionStat` (04_Vision/DUT_SP_VisionTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eState | ET_SP_VisionState | - | Driver state machine state |
| bConn | BOOL | - | TCP connected |
| bTrigPending | BOOL | - | Trigger requested, not yet served |
| rLastTrigPos | LREAL | - | Belt position at last trigger [mm] |
| udiTriggers | UDINT | - | Trigger counter |
| udiItems | UDINT | - | Parsed items counter |
| udiErr | UDINT | - | Communication/protocol errors |
| udiRspMs | UDINT | - | Last response round trip [ms] |
| iOwnerRobot | SINT | - | Robot owning camera control (resiliency) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_VisionStat;` e azzerarla (`st := ST_SP_VisionStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D37:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D38 — TYPE `ST_SP_TrkItem` (05_Tracking/DUT_SP_TrkTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| udiId | UDINT | - | Globally unique id (from camera) |
| uiTypeId | UINT | - | Product type 1..GC_TYPES |
| rCrossCap | LREAL | - | Across-belt coordinate u at capture [mm] |
| rBeltCap | LREAL | - | Belt offset v at capture, upstream of pick line [mm] |
| rEncCap | LREAL | - | Belt encoder coordinate at capture [mm] |
| p2World | ST_SP_Pose2D | - | World pose at capture (feed frame) |
| rWeight | LREAL | - | Part weight [g], 0 = unknown |
| rScore | LREAL | - | Vision score [0..1] |
| eState | ET_SP_ItemState | - |  |
| iReservedBy | SINT | - | Robot id holding the reservation (0 = none) |
| uiAttempts | UINT | - | Pick attempts (retry policy) |
| bTarget | BOOL | - | TRUE = placement target (pattern slot) |
| udiBatchId | UDINT | - | Owning batch for targets |
| uiSlot | UINT | - | Pattern slot for targets (0 = none) |
| rZWorld | LREAL | - |  |
| tAgeMs | UDINT | - | Age since capture [ms], for timeouts |
| bValid | BOOL | - |  |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TrkItem;` e azzerarla (`st := ST_SP_TrkItem#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D38:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D39 — TYPE `ST_SP_ResReq` (05_Tracking/DUT_SP_TrkTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iRobotId | SINT | - | Requesting robot (1..GC_ROBOTS) |
| rRangeFrom | LREAL | - | Robot work range, belt Y offset [mm] |
| rRangeTo | LREAL | - | Robot work range, belt Y offset [mm] |
| uiTypeId | UINT | - | Required type, 0 = any |
| bTargetOnly | BOOL | - | TRUE = only placement targets |
| rMaxWeight | LREAL | - | Tool capacity [g], 0 = unlimited |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ResReq;` e azzerarla (`st := ST_SP_ResReq#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D39:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D40 — TYPE `ST_SP_ResRsp` (05_Tracking/DUT_SP_TrkTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bOk | BOOL | - | Reservation granted |
| iIdx | SINT | - | Queue index of the reserved item |
| stItem | ST_SP_TrkItem | - | Snapshot of the reserved item |
| p3Pick | ST_SP_Pose3D | - | Predicted world pick pose (pick line) |
| rBeltSpd | LREAL | - | Belt speed at reservation [mm/s] |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ResRsp;` e azzerarla (`st := ST_SP_ResRsp#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D40:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D41 — TYPE `ST_SP_TrkCfg` (05_Tracking/DUT_SP_TrkTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Feed enabled |
| sName | STRING(16) | - | Human readable feed name |
| iDir | SINT | - | Belt direction sign (+1 / -1) |
| rWinStart | LREAL | - | Distance pick line -> window start [mm] |
| rWinLen | LREAL | - | Tracking window length [mm] |
| rPickAhead | LREAL | - | Reservation cut-off ahead of pick line [mm] |
| tTimeout | TIME | - | Item tracking timeout |
| astCalib | ARRAY[1..2] OF ST_SP_Transf2D | - | Camera -> feed world 1..GC_CAMS |
| stWorld | ST_SP_Transf2D | - | Feed -> robot world frame (misalignment compensation) |
| rZBelt | LREAL | - | Belt surface height in world frame [mm] |
| rDupTol | LREAL | 25.0 | Duplicate suppression radius across overlapping shots [mm] |
| bDupSameType | BOOL | FALSE | TRUE = deduplicate only identical uiTypeId; FALSE = any type |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TrkCfg;` e azzerarla (`st := ST_SP_TrkCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D41:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D42 — TYPE `ST_SP_TrkStat` (05_Tracking/DUT_SP_TrkTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| uiTracked | UINT | - | Items currently tracked |
| uiReserved | UINT | - | Items reserved by robots |
| udiFed | UDINT | - | Total unique items fed into the queue |
| udiDup | UDINT | - | Duplicate detections merged/suppressed across shots |
| udiPicked | UDINT | - | Total items picked |
| udiLost | UDINT | - | Items lost (timeout / window exit) |
| bWindowBusy | BOOL | - | Window saturated (backpressure signal) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TrkStat;` e azzerarla (`st := ST_SP_TrkStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D42:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D43 — TYPE `ST_SP_PattDef` (06_Pattern/DUT_SP_PatternTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Pattern slot in use |
| sName | STRING(24) | - | Human readable pattern name |
| uiRows | UINT | - | Rows (along belt) |
| uiCols | UINT | - | Columns (across belt) |
| rDx | LREAL | - | Column pitch, across belt [mm] |
| rDy | LREAL | - | Row pitch, along belt [mm] |
| rRotStep | LREAL | - | Rotation step per slot [deg], 0 = keep |
| pBase | ST_SP_Pose2D | - | Base slot pose in FEED frame (u across, v upstream) |
| uiLayers | UINT | - | Number of tray layers (1 = single tier) |
| rLayerH | LREAL | - | Layer height [mm] |
| rZBase | LREAL | - | Z of layer 0 in world [mm] |
| rTrigDist | LREAL | - | Pattern repetition distance [mm] (Distance mode) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_PattDef;` e azzerarla (`st := ST_SP_PattDef#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D43:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D44 — TYPE `ST_SP_BatchDef` (06_Pattern/DUT_SP_PatternTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Batch slot in use |
| sName | STRING(24) | - | Human readable batch name |
| iOutFeed | SINT | - | Outfeed 1..GC_FEEDS |
| uiPattId | UINT | - | Pattern index 1..GC_PATT |
| aiMix | ARRAY[1..8] OF UINT | - | Type mix sequence 1..GC_SEQ (1..GC_TYPES) |
| aiMixCnt | ARRAY[1..8] OF UINT | - | Slots per mix entry 1..GC_SEQ (per layer) |
| udiQty | UDINT | - | Total target quantity |
| eTrig | ET_SP_PattTrig | - | Pattern instance trigger |
| iPriority | SINT | - | Scheduling priority (higher = sooner) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_BatchDef;` e azzerarla (`st := ST_SP_BatchDef#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D44:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D45 — TYPE `ST_SP_BatchStat` (06_Pattern/DUT_SP_PatternTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eState | ET_SP_BatchState | - |  |
| udiDone | UDINT | - | Targets placed |
| udiGen | UDINT | - | Targets generated |
| udiBatchId | UDINT | - | Runtime batch id |
| uiLayer | UINT | - | Current layer being generated |
| udiTrays | UDINT | - | Tray instances generated |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_BatchStat;` e azzerarla (`st := ST_SP_BatchStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D45:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D46 — TYPE `ST_SP_PattCmd` (06_Pattern/DUT_SP_PatternTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bStart | BOOL | - | TRUE = pending StartBatch request |
| bAbort | BOOL | - | TRUE = pending AbortBatch request |
| iFeed | SINT | - | Outfeed the engine drives (1..GC_FEEDS) |
| iBatch | SINT | - | Batch index (for diagnostics) |
| stDef | ST_SP_BatchDef | - | Resolved batch definition snapshot |
| stPatt | ST_SP_PattDef | - | Pattern definition snapshot (g_astPatt) |
| udiBatchId | UDINT | - | Runtime batch id for the engine |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_PattCmd;` e azzerarla (`st := ST_SP_PattCmd#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D46:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D47 — TYPE `ST_SP_RobShare` (07_LoadSharing/DUT_SP_ShareTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iRobotId | SINT | - | 1..GC_ROBOTS |
| bOnline | BOOL | - | Group enabled and homed |
| bFault | BOOL | - | Robot in fault (excluded) |
| bIdle | BOOL | - | Ready to accept a job now |
| uiToolMask | UINT | - | Bitmask of idle tools (bit i-1 = tool i) |
| rLoadPct | LREAL | - | Estimated busyness [0..1] |
| udiPicks | UDINT | - | Lifetime picks (balancing metric) |
| udiPlaces | UDINT | - | Lifetime placements |
| p2Now | ST_SP_Pose2D | - | Current world pose (greedy distance metric) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RobShare;` e azzerarla (`st := ST_SP_RobShare#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D47:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D48 — TYPE `ST_SP_Offer` (07_LoadSharing/DUT_SP_ShareTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iFeed | SINT | - | Feed offering the item 1..GC_FEEDS |
| uiTypeId | UINT | - | Product type (0 = unknown) |
| rBeltOff | LREAL | - | Current upstream offset [mm] |
| stW | ST_SP_Pose2D | - | Item world pose (greedy metric) |
| bTarget | BOOL | - | TRUE = placement target offer |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Offer;` e azzerarla (`st := ST_SP_Offer#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D48:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D49 — TYPE `ST_SP_ShareCfg` (07_LoadSharing/DUT_SP_ShareTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| aeStrat | ARRAY[1..8] OF ET_SP_ShareStrategy | - | Per feed 1..GC_FEEDS |
| aabManual | ARRAY[1..8] OF ARRAY[1..4] OF BOOL | - | Manual matrix 1..GC_FEEDS x 1..GC_ROBOTS |
| arRatio | ARRAY[1..4] OF LREAL | - | User share ratios (>0) 1..GC_ROBOTS |
| arRangeFrom | ARRAY[1..8] OF ARRAY[1..4] OF LREAL | - | mm 1..GC_FEEDS x 1..GC_ROBOTS |
| arRangeTo | ARRAY[1..8] OF ARRAY[1..4] OF LREAL | - | mm 1..GC_FEEDS x 1..GC_ROBOTS |
| audTypeMask | ARRAY[1..4] OF UDINT | - | Bit i-1 = type i allowed 1..GC_ROBOTS |
| eMatch | ET_SP_MatchMode | - | Matched/Unmatched/Mixed |
| bStrictOrder | BOOL | - | Strict priority order mode (organic) |
| rPickBias | LREAL | - | Pick vs place planning bias [0..1] |
| aiOutfeedMap | ARRAY[1..8] OF SINT | - | Infeed -> outfeed, 0=none 1..GC_FEEDS |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ShareCfg;` e azzerarla (`st := ST_SP_ShareCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D49:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D50 — TYPE `ET_SP_MvKind` (08_Robot/DUT_SP_RobotTypes.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| None | 0 |
| Home | 1 |
| LinearAbs | 2 |
| TrackAbs | 3 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_MvKind;`.
2. Assegnare ogni letterale (es. `x := ET_SP_MvKind#None;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D50:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D51 — TYPE `ST_SP_BeltFrame` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Feed wired for native tracking (PRG call) |
| stWorld | ST_SP_Transf2D | - | Feed -> world frame transform (frame source) |
| iDir | SINT | - | Belt travel sign (+1 / -1) from the feed config |
| rOrgX | LREAL | - | Belt CS origin X in world/MCS [mm] (feed origin = pick line center) |
| rOrgY | LREAL | - | Belt CS origin Y in world/MCS [mm] |
| rOrgZ | LREAL | - | Belt CS origin Z in world/MCS [mm] = rZBelt |
| rPhi | LREAL | - | Belt CS rotation in world [deg], x-axis along belt travel |
| rSyncDist | LREAL | - | TrackOptions.SyncIn.ConveyorDistance [mm], always > 0 (FW 2026.6) |
| rZBelt | LREAL | - | Belt surface height in world [mm] (item Z reference) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_BeltFrame;` e azzerarla (`st := ST_SP_BeltFrame#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D51:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D52 — TYPE `ST_SP_TrkSyncIn` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| ConveyorDistance | LREAL | - | Sync-in conveyor distance [mm], must be > 0 (FW 2026.6: 0 => error 9006) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TrkSyncIn;` e azzerarla (`st := ST_SP_TrkSyncIn#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D52:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D53 — TYPE `ST_SP_TrkOpt` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| SyncIn | ST_SP_TrkSyncIn | - | Sync-in window parameters |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TrkOpt;` e azzerarla (`st := ST_SP_TrkOpt#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D53:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D54 — TYPE `ST_SP_ToolCfg` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Tool present |
| sName | STRING(16) | - | Human readable tool name |
| bSuction | BOOL | - | TRUE = suction, FALSE = mechanical grip |
| rMaxWeight | LREAL | - | Payload capacity [g], 0 = unlimited |
| uiPickOutCh | UINT | - | Pick output channel (0 = auto robot*tool) |
| uiPlaceOutCh | UINT | - | Place output channel (0 = auto) |
| uiFbkInCh | UINT | - | Feedback input channel (0 = auto) |
| tGrip | TIME | - | Grip duration before motion release |
| tRelease | TIME | - | Release duration before departure |
| rAdvance | LREAL | - | Advance timing distance (cut-off margin) [mm] |
| uiCups | UINT | - | Active cups 1..GC_CUPS |
| bSingleType | BOOL | - | Tool holds one type per cycle (no mixing) |
| astCups | ARRAY[1..4] OF ST_SP_Point3D | - | Cup offsets rel. TCP [mm] 1..GC_CUPS |
| auiCupFbkCh | ARRAY[1..4] OF UINT | - | Per-cup vacuum feedback channels (0 = tool fbk) 1..GC_CUPS |
| rMatchTol | LREAL | - | Cluster cup-to-item match tolerance [mm] |
| rCapCog | LREAL | - | Max CoG offset from TCP [mm], 0 = check off |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ToolCfg;` e azzerarla (`st := ST_SP_ToolCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D54:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D55 — TYPE `ST_SP_ToolStat` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bGripping | BOOL | - | Grip sequence running |
| bHolding | BOOL | - | Part held (feedback based when available) |
| bFbk | BOOL | - | Raw feedback input |
| udiPicks | UDINT | - |  |
| udiPlaces | UDINT | - |  |
| abCupFbk | ARRAY[1..4] OF BOOL | - | Per-cup vacuum feedback at grip end 1..GC_CUPS |
| uiCupOk | UINT | - | Cups confirmed holding at the last sync grip |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ToolStat;` e azzerarla (`st := ST_SP_ToolStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D55:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D56 — TYPE `ST_SP_PathOff` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rAppDx | LREAL | - | Approach: X offset from pick/place point |
| rAppDy | LREAL | - | Approach: Y offset |
| rAppDz | LREAL | - | Approach: Z offset above point |
| rDepDx | LREAL | - | Depart: X offset |
| rDepDy | LREAL | - | Depart: Y offset |
| rDepDz | LREAL | - | Depart: Z offset |
| rPtDz | LREAL | - | Point Z correction (belt tolerance) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_PathOff;` e azzerarla (`st := ST_SP_PathOff#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D56:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D57 — TYPE `ST_SP_RobCfg` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bUsed | BOOL | - | Robot enabled |
| sName | STRING(16) | - | Human readable name |
| uiGroup | UINT | - | Firmware kinematic group index (adapter) |
| uiNumTools | UINT | - | Configured tools 1..GC_TOOLS |
| astTools | ARRAY[1..4] OF ST_SP_ToolCfg | - | 1..GC_TOOLS |
| rVelApp | LREAL | - | Approach/depart moves |
| rVelTrack | LREAL | - | Tracking pick move (belt synchronized) |
| rVelPlace | LREAL | - | Place moves |
| rAcc | LREAL | - | Acceleration [mm/s2] |
| rDec | LREAL | - | Deceleration [mm/s2] |
| ePrecApp | ET_SP_Precision | - |  |
| ePrecPick | ET_SP_Precision | - |  |
| ePrecPlace | ET_SP_Precision | - |  |
| rZoneTight | LREAL | - | ZoneTight blending radius [mm] |
| rZoneWide | LREAL | - | ZoneWide blending radius [mm] |
| rZSafe | LREAL | - | Safe travel height above belt [mm] |
| tHomeTimeout | TIME | - | Homing supervision |
| eGripMode | ET_SP_GripMode | - | Sync / Partial / Async |
| uiMaxGrip | UINT | - | Max parts per cycle 1..GC_CUPS |
| bVerifyPick | BOOL | - | Verify grip feedback at pick |
| bVerifyPlace | BOOL | - | Verify release/place |
| bDeferVerify | BOOL | - | Deferred: verify holding at place |
| uiRetries | UINT | - | Retry count before NG |
| abiCamOwner | ARRAY[1..2] OF BOOL | - | TRUE = this robot owns camera i 1..GC_CAMS |
| astOff | ARRAY[1..8] OF ARRAY[1..32] OF ST_SP_PathOff | - | 1..GC_FEEDS x 1..GC_TYPES |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RobCfg;` e azzerarla (`st := ST_SP_RobCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D57:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D58 — TYPE `ST_SP_JobItem` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| stItem | ST_SP_TrkItem | - | Reserved source item (product or target) |
| iIdx | SINT | - | Queue index in the pick feed |
| iIdxPlace | SINT | - | Queue index of the target in the place feed |
| iFeedPick | SINT | - | Pick feed (0 for place-only items) |
| iFeedPlace | SINT | - | Place feed (0 for pick-only items) |
| stTgt | ST_SP_TrkItem | - | v1.4 placement target snapshot (belt capture data driving the native tracked place) |
| uiTool | UINT | - | Tool used |
| uiCup | UINT | - | Cup used 1..GC_CUPS |
| p3Pick | ST_SP_Pose3D | - | Pick pose (world, predicted) |
| p3Place | ST_SP_Pose3D | - | Place pose (world, target) |
| bPick | BOOL | - | Job includes the pick |
| bPlace | BOOL | - | Job includes the place |
| bPicked | BOOL | - | Progress flags |
| bPlaced | BOOL | - |  |
| bVerified | BOOL | - |  |
| bNg | BOOL | - | Item failed (retry exhausted) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_JobItem;` e azzerarla (`st := ST_SP_JobItem#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D58:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D59 — TYPE `ST_SP_Job` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eKind | ET_SP_JobKind | - | Pick / Place / PickPlace |
| iRobot | SINT | - | Assigned robot |
| uiCount | UINT | - | Valid items 1..GC_CUPS |
| astItems | ARRAY[1..4] OF ST_SP_JobItem | - | 1..GC_CUPS |
| eExec | ET_SP_GripExec | - | AsyncCup = sequential, SyncAll = one descent |
| stSyncPick | ST_SP_Pose3D | - | Cluster TCP pose at the pick event (SyncAll) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_Job;` e azzerarla (`st := ST_SP_Job#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D59:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D60 — TYPE `ST_SP_RobCmd` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bHome | BOOL | - | Start homing sequence |
| bStop | BOOL | - | Immediate controlled stop |
| bReset | BOOL | - | Fault reset |
| bPause | BOOL | - | Freeze job (items stay reserved) |
| bResume | BOOL | - | Resume from freeze |
| bDryRun | BOOL | - | Trial run lock: no grip, raised Z |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RobCmd;` e azzerarla (`st := ST_SP_RobCmd#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D60:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D61 — TYPE `ST_SP_RobStat` (08_Robot/DUT_SP_RobotTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eState | ET_SP_RobState | - |  |
| bOnline | BOOL | - |  |
| bReady | BOOL | - | Homed, enabled, accepting jobs |
| bBusy | BOOL | - |  |
| bFault | BOOL | - |  |
| bPaused | BOOL | - |  |
| bHolding | BOOL | - | Any tool holding |
| bDryRun | BOOL | - |  |
| uiCurTool | UINT | - |  |
| uiCurFeed | SINT | - |  |
| uiCurPlaceFeed | UINT | - |  |
| bTrkPlace | BOOL | - |  |
| uiJobCnt | UINT | - | Items in current job |
| uiToolMask | UINT | - | Bit i-1 = tool i idle (balancer input) |
| p2Now | ST_SP_Pose2D | - | Current world pose |
| udiCycles | UDINT | - | Completed cycles |
| udiPicks | UDINT | - | Lifetime picks (balancer metric) |
| udiPlaces | UDINT | - | Lifetime placements |
| rLoadPct | LREAL | - | Load metric for the balancer [0..1] |
| uiErrId | UINT | - | Last error code (0 = none) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RobStat;` e azzerarla (`st := ST_SP_RobStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D61:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D62 — TYPE `ST_SP_FeedIo` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iFeed | SINT | - | 1..GC_FEEDS |
| bUsed | BOOL | - |  |
| rEnc | LREAL | - | Current belt encoder [mm] |
| rSpeed | LREAL | - | Signed belt speed [mm/s] |
| stStat | ST_SP_TrkStat | - | Queue statistics |
| rNearOff | LREAL | - | Nearest item offset upstream [mm] |
| stPickLineW | ST_SP_Pose2D | - | Pick line origin in world (greedy metric) |
| bCalibOk | BOOL | - | At least one camera calibrated |
| bIsOutfeed | BOOL | - | TRUE = placement feed (pattern engine) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_FeedIo;` e azzerarla (`st := ST_SP_FeedIo#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D62:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D63 — TYPE `ST_SP_SysCmd` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bStart | BOOL | - |  |
| bStop | BOOL | - |  |
| bPause | BOOL | - |  |
| bResume | BOOL | - |  |
| bReset | BOOL | - |  |
| bHomeAll | BOOL | - |  |
| bDryRun | BOOL | - | Trial run lock (system wide) |
| iStartBatch | SINT | - | Batch index to start (0 = none) |
| iStopBatch | SINT | - | Batch index to stop (0 = none) |
| bClearItems | BOOL | - | Purge all tracking queues |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_SysCmd;` e azzerarla (`st := ST_SP_SysCmd#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D63:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D64 — TYPE `ST_SP_SysCfg` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| tStartStage | TIME | - | Delay between startup stages |
| bResilience | BOOL | - | TRUE = continue on robot loss |
| bAutoRestart | BOOL | - | Automatic restart after fault clear |
| bStopConvsOnPause | BOOL | - | Stop conveyors during pause |
| bZoneGuard | BOOL | - | TRUE = enforce shared-zone exclusion |
| bColAdv | BOOL | - | TRUE = use SP_Collision (zones + speed + separation) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_SysCfg;` e azzerarla (`st := ST_SP_SysCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D64:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D65 — TYPE `ST_SP_SysStat` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| eState | ET_SP_SysState | - |  |
| bReady | BOOL | - | All stages up, production possible |
| bRunning | BOOL | - |  |
| bPaused | BOOL | - |  |
| bDryRun | BOOL | - |  |
| uiRobotsRun | UINT | - | Robots in production |
| uiRobotsFault | UINT | - |  |
| udiItemsInSys | UDINT | - | Items currently tracked (sum) |
| uiErrId | UINT | - |  |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_SysStat;` e azzerarla (`st := ST_SP_SysStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D65:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D66 — TYPE `ST_SP_DispReq` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bReq | BOOL | - | Request valid this cycle |
| iFeed | SINT | - | Feed to reserve from |
| uiTypeId | UINT | - | Type requested (0 = any) |
| bTargetOnly | BOOL | - | TRUE = target reservation (place) |
| rMaxWeight | LREAL | - | Tool capacity [g] |
| bCluster | BOOL | - | TRUE = cluster reservation (Sync grip) |
| stCl | ST_SP_ClReq | - | Cluster request payload |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_DispReq;` e azzerarla (`st := ST_SP_DispReq#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D66:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D67 — TYPE `ST_SP_CancelReq` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bCancel | BOOL | - | Cancel request valid |
| stJob | ST_SP_Job | - | Partial job whose items must be released |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_CancelReq;` e azzerarla (`st := ST_SP_CancelReq#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D67:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D68 — TYPE `ST_SP_StatEv` (09_Production/DUT_SP_SysTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bCycle | BOOL | - | TRUE = cycle-complete event (AddCycle) |
| bPlace | BOOL | - | TRUE = place event, FALSE = pick event |
| bOk | BOOL | - | TRUE = good part, FALSE = NG part |
| iFeed | SINT | - | Feed the event belongs to (1..GC_FEEDS) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_StatEv;` e azzerarla (`st := ST_SP_StatEv#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D68:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D69 — TYPE `ST_SP_RetainData` (10_Persistence/DUT_SP_PersistTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| uiVer | UINT | - | Blob layout version |
| uiSum | UDINT | - | Additive checksum of the payload |
| bInit | BOOL | - | TRUE after first valid restore |
| sRecipe | STRING(32) | - | Last loaded recipe name |
| udiPickTotal | UDINT | - | Lifetime picks |
| udiPlaceTotal | UDINT | - | Lifetime placements |
| aiCamOwner | ARRAY[1..2] OF SINT | - |  |
| astBatch | ARRAY[1..8] OF ST_SP_BatchStat | - |  |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RetainData;` e azzerarla (`st := ST_SP_RetainData#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D69:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D70 — TYPE `ST_SP_RecipeHdr` (10_Persistence/DUT_SP_PersistTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| sName | STRING(32) | - | Recipe name (file name stem) |
| uiVer | UINT | - | Format version |
| uiSum | UDINT | - | Content checksum (informational) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RecipeHdr;` e azzerarla (`st := ST_SP_RecipeHdr#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D70:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D71 — TYPE `ET_SP_GripExec` (13_MultiGrip/DUT_SP_MultiGrip.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| AsyncCup | 0 |
| SyncAll | 1 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_GripExec;`.
2. Assegnare ogni letterale (es. `x := ET_SP_GripExec#AsyncCup;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D71:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D72 — TYPE `ST_SP_ClReq` (13_MultiGrip/DUT_SP_MultiGrip.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| iRobotId | SINT | - | Requesting robot 1..GC_ROBOTS |
| rRangeFrom | LREAL | - | Robot work range, belt offset [mm] |
| rRangeTo | LREAL | - | Robot work range, belt offset [mm] |
| uiTypeId | UINT | - | Required type, 0 = any |
| rMaxWeight | LREAL | - | Tool payload capacity [g], 0 = unlimited |
| uiCups | UINT | - | Active cups offered to the planner 1..GC_CUPS |
| astCup | ARRAY[1..4] OF ST_SP_Point3D | - | Cup offsets rel. TCP [mm] 1..GC_CUPS |
| bSingleType | BOOL | - | TRUE = no mixed product types per cluster |
| rMatchTol | LREAL | - | Max cup-to-item residual [mm] |
| rMinGap | LREAL | - | Min distance between picked items [mm], 0 = off |
| rMaxCog | LREAL | - | Max CoG offset from TCP [mm], 0 = check off |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ClReq;` e azzerarla (`st := ST_SP_ClReq#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D72:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D73 — TYPE `ST_SP_ClRsp` (13_MultiGrip/DUT_SP_MultiGrip.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bOk | BOOL | - | TRUE = at least the anchor was reserved |
| bSync | BOOL | - | TRUE = synchronized multi-pick possible |
| uiN | UINT | - | Members reserved 1..GC_CUPS |
| aiIdx | ARRAY[1..4] OF SINT | - | Queue slot per member 1..GC_CUPS |
| aCup | ARRAY[1..4] OF SINT | - | Cup id per member (1-based) 1..GC_CUPS |
| astRsp | ARRAY[1..4] OF ST_SP_ResRsp | - | Per-member reservation 1..GC_CUPS |
| stTcp | ST_SP_Pose3D | - | Synchronized TCP pose at the pick event |
| rTotWeight | LREAL | - | Cluster total weight [g], 0 = unknown |
| rCogOff | LREAL | - | CoG offset from TCP [mm] (0 = unknown) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ClRsp;` e azzerarla (`st := ST_SP_ClRsp#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D73:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D74 — TYPE `ET_SP_ColAct` (14_Collision/DUT_SP_ColTypes.st)

**Enumerato — valori attesi (nome := valore):**

| Literal | Valore |
|---|---|
| None | 0 |
| WaitZone | 1 |
| SlowZone | 2 |
| SepSlow | 3 |
| SepStop | 4 |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `x : ET_SP_ColAct;`.
2. Assegnare ogni letterale (es. `x := ET_SP_ColAct#None;`) e leggere il valore numerico in Watch.
3. Verificare corrispondenza con la tabella e univocità dei valori (nessun duplicato).
4. Verificare che codice cliente e FB usino solo letterali di questo enumerato (ricerca in tutti i 73 fogli).

**Criterio UT-D74:** valori corrispondenti, nessun valore duplicato, nessun uso di valori numerici grezzi al posto dei letterali nel codice.

---

### UT-D75 — TYPE `ST_SP_ColCfg` (14_Collision/DUT_SP_ColTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bEnable | BOOL | - |  |
| bDynaSep | BOOL | - |  |
| bSepAll | BOOL | - |  |
| rSlowDist | LREAL | - |  |
| rStopDist | LREAL | - |  |
| aiPriority | ARRAY[1..4] OF SINT | - |  |
| arZoneLim | ARRAY[1..8] OF LREAL | - |  |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ColCfg;` e azzerarla (`st := ST_SP_ColCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D75:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D76 — TYPE `ST_SP_ZoneDiag` (14_Collision/DUT_SP_ColTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bHeld | BOOL | - | Zone occupied by at least one robot |
| iHolder | SINT | - | Current holder robot id (0 = free) |
| uiWaiters | UINT | - | Robots currently waiting for this zone |
| udiGrant | UDINT | - | Total grants handed out (statistics) |
| udiCont | UDINT | - | Contention events (request while held) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_ZoneDiag;` e azzerarla (`st := ST_SP_ZoneDiag#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D76:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D77 — TYPE `ST_SP_RobCol` (14_Collision/DUT_SP_ColTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bGrant | BOOL | - | TRUE = robot free to move |
| rVelScale | LREAL | - | Velocity scale 0.1..1.0 |
| eWhy | ET_SP_ColAct | - | Reason of the current limitation |
| udiWaitMs | UDINT | - | Accumulated frozen time [ms] (layout KPI) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_RobCol;` e azzerarla (`st := ST_SP_RobCol#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D77:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D78 — TYPE `ST_SP_OeeView` (15_Professional/DUT_SP_ProTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| rAvail | LREAL | - | Availability = run time / planned time [0..1] |
| rPerf | LREAL | - | Performance = ideal cycle x count / run time [0..1] |
| rQual | LREAL | - | Quality = good picks / total picks [0..1] |
| rOee | LREAL | - | OEE = A x P x Q [0..1] |
| udiPlanMs | UDINT | - | Planned (shift) time [ms] |
| udiRunMs | UDINT | - | Productive time [ms] |
| udiDownMs | UDINT | - | Downtime (fault) [ms] |
| udiCycles | UDINT | - | Cycles in the current shift |
| udiGood | UDINT | - | Good picks in the current shift |
| udiNg | UDINT | - | Failed picks in the current shift |
| udiFaults | UDINT | - | Fault events in the current shift |
| rMtbfMin | LREAL | - | Mean time between faults [min], EMA smoothed |
| rMttrMin | LREAL | - | Mean time to repair [min], EMA smoothed |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_OeeView;` e azzerarla (`st := ST_SP_OeeView#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D78:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D79 — TYPE `ST_SP_MaintCfg` (15_Professional/DUT_SP_ProTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| audiRobCycles | ARRAY[1..4] OF UDINT | - |  |
| audiCamShots | ARRAY[1..2] OF UDINT | - |  |
| audiConvMin | ARRAY[1..8] OF UDINT | - |  |
| udiPumpMin | UDINT | - |  |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_MaintCfg;` e azzerarla (`st := ST_SP_MaintCfg#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D79:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D80 — TYPE `ST_SP_MaintStat` (15_Professional/DUT_SP_ProTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| audiRobCycles | ARRAY[1..4] OF UDINT | - |  |
| audiRobPct | ARRAY[1..4] OF LREAL | - | Load 0..1 |
| abRobDue | ARRAY[1..4] OF BOOL | - | Maintenance due |
| audiCamShots | ARRAY[1..2] OF UDINT | - |  |
| audiCamPct | ARRAY[1..2] OF LREAL | - |  |
| abCamDue | ARRAY[1..2] OF BOOL | - |  |
| audiConvMin | ARRAY[1..8] OF UDINT | - |  |
| audiConvPct | ARRAY[1..8] OF LREAL | - |  |
| abConvDue | ARRAY[1..8] OF BOOL | - |  |
| udiPumpMin | UDINT | - |  |
| rPumpPct | LREAL | - |  |
| bPumpDue | BOOL | - |  |
| bAnyDue | BOOL | - | TRUE when at least one threshold is reached |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_MaintStat;` e azzerarla (`st := ST_SP_MaintStat#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D80:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-D81 — TYPE `ST_SP_TestRes` (15_Professional/DUT_SP_ProTypes.st)

**Struttura — campi e default:**

| Campo | Tipo | Default | Descrizione |
|---|---|---|---|
| bPass | BOOL | - | TRUE = all checks passed |
| uiChecks | UINT | - | Number of checks executed |
| uiFails | UINT | - | Number of failed checks |
| auiFail | ARRAY[1..16] OF UINT | - |  |
| sMsg | STRING(80) | - |  |
| stRun | Yt_YA_RTC_Struct | - | Wall clock of the last run (v1.8.0) |

**Procedura:**

1. In `PRG_UT_Scratch` dichiarare `st : ST_SP_TestRes;` e azzerarla (`st := ST_SP_TestRes#();` oppure lasciare il default di dichiarazione).
2. Dopo il primo ciclo, leggere in Watch tutti i campi e verificare i valori della colonna *Default* (dove previsti).
3. Scrivere valori distinti in ogni campo e rileggerli nel ciclo successivo (verifica di scrittura/lettura).
4. Verificare che i campi usati come `VAR_IN_OUT` nei chiamanti vengano SEMPRE assegnati (nessun campo lasciato invariato per errore).

**Criterio UT-D81:** default rispettati, scrittura/lettura coerente, nessun campo non assegnato dove richiesto.

---

### UT-G01 — `01_Common/GVL_SP_Const.st` — Costanti di progetto

**Procedura:** Verificare i valori di `GC_ROBOTS=4, GC_FEEDS=8, GC_CAMS=2, GC_TOOLS=4, GC_TYPES=32, GC_CUPS=4, GC_QUEUE=64, GC_LOG_N=256, GC_ALARM_N=64, GC_ZONES=4, GC_DUP_TOL_MM assente (in GVL_SP_Trk)`, `GC_PI`, `GC_DEG2RAD`, `GC_RAD2DEG`, `GC_ASCII95` (95 caratteri). Ogni const deve essere usata solo nel foglio dati in cui è dichiarata (regola iCube).

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR CONSTANT | GC_SP_VER_MAJOR | UINT | 1 | SmartPick_iC major version |
| VAR CONSTANT | GC_SP_VER_MINOR | UINT | 8 | SmartPick_iC minor version |
| VAR CONSTANT | GC_SP_VER_BUILD | UINT | 0 | SmartPick_iC build number |
| VAR CONSTANT | GC_ROBOTS | SINT | 4 | Max robots / kinematic groups |
| VAR CONSTANT | GC_FEEDS | SINT | 8 | Max feeds (tracked conveyors) |
| VAR CONSTANT | GC_CAMS | SINT | 2 | Max cameras |
| VAR CONSTANT | GC_TOOLS | SINT | 4 | Max tools per robot |
| VAR CONSTANT | GC_TYPES | SINT | 32 | Max product types |
| VAR CONSTANT | GC_CUPS | SINT | 4 | Max cups/tool => parts per cycle |
| VAR CONSTANT | GC_SEQ | SINT | 8 | Max type mix entries per batch |
| VAR CONSTANT | GC_QUEUE | SINT | 64 | Max tracked items per feed |
| VAR CONSTANT | GC_LAYERS | SINT | 4 | Max tray layers per pattern |
| VAR CONSTANT | GC_PATT | SINT | 8 | Max place patterns |
| VAR CONSTANT | GC_PATT_SLOTS | SINT | 16 | Max slots per pattern (rows x cols) |
| VAR CONSTANT | GC_BATCHES | SINT | 8 | Max batch definitions |
| VAR CONSTANT | GC_LOG_N | UINT | 256 | Logger ring buffer depth |
| VAR CONSTANT | GC_ALARM_N | UINT | 64 | Alarm registry depth |
| VAR CONSTANT | GC_MOVAVG_N | SINT | 8 | Speed filter taps |
| VAR CONSTANT | GC_STRCFG | INT | 128 | Generic config string length |
| VAR CONSTANT | GC_STRMSG | INT | 120 | Message string length |
| VAR CONSTANT | GC_ZONES | SINT | 4 | Max interlock zones (R-05 zone guard) |
| VAR CONSTANT | GC_ZONE_NONE | SINT | 0 | Zone id "unguarded" |
| VAR CONSTANT | GC_CALIB_PTS | SINT | 8 | Max 2D calibration point pairs |
| VAR CONSTANT | GC_RATE_WIN | UDINT | 10000 | Rolling throughput window [ms] |
| VAR CONSTANT | GC_ASCII95 | STRING(95) | ' !"#$%&''()*+,-./0123456789: |  |
| VAR CONSTANT | GC_PI | LREAL | 3.14159265358979323846 | pi [rad], trig use only |
| VAR CONSTANT | GC_2PI | LREAL | 6.28318530717958647692 | 2*pi [rad], trig use only |
| VAR CONSTANT | GC_DEG2RAD | LREAL | 0.01745329251994329577 | pi / 180 |
| VAR CONSTANT | GC_RAD2DEG | LREAL | 57.29577951308232087680 | 180 / pi |
| VAR CONSTANT | GC_90 | LREAL | 90.0 | Quarter turn [deg] |
| VAR CONSTANT | GC_180 | LREAL | 180.0 | Half turn [deg] |
| VAR CONSTANT | GC_360 | LREAL | 360.0 | Full turn [deg] |
| VAR CONSTANT | GC_ITEM_AGE_MS | UDINT | 60000 | Default item tracking timeout [ms] |
| VAR CONSTANT | GC_SPEED_MIN | LREAL | 0.5 | Deadband for speed filter [u/s] |
| VAR CONSTANT | GC_DIST_EPS | LREAL | 0.01 | Distance epsilon [u] |
| VAR CONSTANT | GC_ANG_EPS | LREAL | 0.03 | Angle epsilon [deg] |
| VAR CONSTANT | GC_REAL_MAX | LREAL | 1.0E12 | Sentinel for "infinite" distance |
| VAR CONSTANT | GC_ID_NONE | SINT | 0 | "No robot / no feed" identifier |

**Criterio UT-G01:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G02 — `05_Tracking/GVL_SP_Trk.st` — Costanti tracking

**Procedura:** Verificare `GC_WIN_BEHIND = 20.0` e `GC_DUP_TOL_MM = 25.0`. Modificare `GC_DUP_TOL_MM` a 50.0 in un test separato e verificare che il filtro doppioni si allarghi (TK-01): poi ripristinare.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR CONSTANT | GC_WIN_BEHIND | LREAL | 20.0 |  |
| VAR CONSTANT | GC_DUP_TOL_MM | LREAL | 25.0 |  |

**Criterio UT-G02:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G03 — `04_Vision/GVL_SP_Vision.st` — GVL visione

**Procedura:** Verificare presenza e visibilità da `04_Vision` e `12_Application`. Stato online dei descrittori camera.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR CONSTANT | GC_SOCK_RX | DINT | 512 | Socket receive buffer size [bytes] |
| VAR CONSTANT | GC_SOCK_TX | DINT | 128 | Socket transmit buffer size [bytes] |
| VAR CONSTANT | GC_VIS_MAX | SINT | 16 | Max items parsed per image |
| VAR CONSTANT | GC_VIS_MAX2 | SINT | 32 | Camera out-queue depth (harvest) |
| VAR CONSTANT | GC_VIS_IDLE | UDINT | 60 | Idle time considered end-of-response [ms] |

**Criterio UT-G03:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G04 — `12_Application/GVL_SP_Fw.st` — Stato firmware

**Procedura:** Verificare i campi di versione/identificazione coerenti con `GC_SP_VER_*`. Dopo il download: leggere in Watch.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | g_eFwStatMode | SINT | 0 | 0 = proxy via enable, 1 = inject real status |
| VAR | g_abFwGrpReady | ARRAY[1..4] OF BOOL | - | Group enabled / ready   1..GC_ROBOTS |
| VAR | g_abFwGrpRef | ARRAY[1..4] OF BOOL | - | Group referenced / homed 1..GC_ROBOTS |
| VAR | g_eTrkMode | SINT | 0 | ------------------- FW-1: conveyor tracking mode ------------------- |
| VAR | g_abPlaceTrack | ARRAY[1..8] OF BOOL | - | 1..GC_FEEDS |

**Criterio UT-G04:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G05 — `12_Application/GVL_SP_Hmi.st` — Comandi HMI

**Procedura:** Verificare che `stHmi` sia leggibile/scrivibile da Watch WT_1. Comandi: bStart, bStop, bReset, bEStop, bPause, bAuto, bResilience.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | g_hmiCmd | ST_SP_SysCmd | - | ---------------- Commands (HMI writes, logic consumes) ------------- |
| VAR | bSaveRecipe | BOOL | - | Export g_sRecipeName |
| VAR | bLoadRecipe | BOOL | - | Import g_sRecipeName |
| VAR | sRecipeName | STRING(32) | 'recipe1' |  |
| VAR | bAckAll | BOOL | - | Alarm acknowledge all |
| VAR | bExportLog | BOOL | - | Dump the log ring to file |
| VAR | g_hmiSysStat | ST_SP_SysStat | - | ---------------- Status (logic writes, HMI reads) ------------------ |
| VAR | g_astHmiRob | ARRAY[1..4] OF ST_SP_RobStat | - | Robot status mirrors for the HMI (one row per robot) 1..GC_ROBOTS |
| VAR | g_astHmiFeed | ARRAY[1..8] OF ST_SP_FeedIo | - | Feed/conveyor status mirrors for the HMI 1..GC_FEEDS |
| VAR | g_astHmiCam | ARRAY[1..2] OF ST_SP_VisionStat | - | Camera status mirrors for the HMI 1..GC_CAMS |
| VAR | g_stHmiStats | ST_SP_Counters | - | Production counters mirror (OEE page) |
| VAR | rHmiPiecesPerH | LREAL | - | Pieces-per-hour KPI computed by Main |
| VAR | g_astHmiAlarm | ARRAY[1..8] OF ST_SP_Alarm | - | ---------------- Diagnostics views (refreshed cyclically) ---------- |
| VAR | g_astHmiLog | ARRAY[1..8] OF ST_SP_LogEntry | - | Last 8 log entries for the HMI list box |
| VAR | sHmiRecipeState | STRING(24) | - | Recipe operation feedback |
| VAR | bApplyConfig | BOOL | - | ---------------- Wizard / online adjustment ------------------------ |
| VAR | g_aiCamModel | ARRAY[1..2] OF SINT | - |  |
| VAR | bRunSelfTest | BOOL | - | Run the startup self-test suite |
| VAR | bShiftReset | BOOL | - | Reset the OEE shift accumulator |
| VAR | bMaintReset | BOOL | - | Reset the maintenance counters |
| VAR | g_stHmiOee | ST_SP_OeeView | - | OEE snapshot (OEE page) |
| VAR | rIdealCycleMs | LREAL | 2000.0 | Ideal cycle time per piece [ms] (performance reference, editable) |
| VAR | g_stHmiMaint | ST_SP_MaintStat | - | Maintenance counters and due flags (maintenance page) |
| VAR | g_stHmiTest | ST_SP_TestRes | - | Self-test result (diagnostics page) |
| VAR | g_astHmiCol | ARRAY[1..4] OF ST_SP_RobCol | - | Advanced collision guard diagnostics (R-05b diagnostics page) 1..GC_ROBOTS |

**Criterio UT-G05:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G06 — `12_Application/GVL_SP_Inst.st` — Istanze principali

**Procedura:** Verificare la presenza di `stCam[1..GC_CAMS]`, `astRob[1..GC_ROBOTS]`, `stCol`, `stZone[1..GC_ZONES]`. Ispezionare i primi cicli: tutti gli FB sono istanziati e il primo `Step`/`Run` produce output plausibili.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | g_Sys | SP_System | - | System orchestrator: staged startup, resiliency, batch registry |
| VAR | g_Disp | SP_Dispatch | - | Dispatcher: load balancer + reservation/job handshake mailbox |

**Criterio UT-G06:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G07 — `12_Application/GVL_SP_Io.st` — I/O e nastro

**Procedura:** Verificare `stConv[1..GC_FEEDS]` con `rReqFactor`, `rBeltSpeed`, `bEnable`. Con il simulatore: attivare `bEnable` e verificare avanzamento encoder.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | bEStopOk | BOOL | TRUE | Emergency stop chain healthy |
| VAR | bSafetyOk | BOOL | TRUE | Guards / scanners healthy |
| VAR | abPickOut | ARRAY[1..16] OF BOOL | - | Tool signals: PICK (out), PLACE (out), FEEDBACK (in) - MotoPick 4 spec 1..GC_ROBOTS*GC_TOOLS |
| VAR | abPlaceOut | ARRAY[1..16] OF BOOL | - | Place/grip digital outputs (robot x tool channel map) 1..GC_ROBOTS*GC_TOOLS |
| VAR | abToolFbkIn | ARRAY[1..16] OF BOOL | - | Grip feedback inputs (looped back in simulation) 1..GC_ROBOTS*GC_TOOLS |
| VAR | grConvDrive | ARRAY[1..8] OF REAL | - | Conveyor drive: analog speed factor per feed (0.0 .. 1.0) 1..GC_FEEDS |
| VAR | abTraySensor | ARRAY[1..8] OF BOOL | - | Tray / light barrier sensors per outfeed 1..GC_FEEDS |

**Criterio UT-G07:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G08 — `12_Application/GVL_SP_Prod.st` — Produzione e KPI

**Procedura:** Verificare `stSys`, `stStats`, `stOee`, `gastBatch[1..GC_BATCHES]`, `gastAlarm`, `stLog`. Azzerare con i metodi dedicati e verificare il ritorno a zero.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR RETAIN | g_stRetain | ST_SP_RetainData | - | Power-failure continuity blob (managed by SP_RetainMgr) |
| VAR | g_astRobStat | ARRAY[1..4] OF ST_SP_RobStat | - | 1..GC_ROBOTS |
| VAR | g_astFeedIo | ARRAY[1..8] OF ST_SP_FeedIo | - | 1..GC_FEEDS |
| VAR | g_abCamOwnerCfg | ARRAY[1..2] OF ARRAY[1..4] OF BOOL | - | 1..GC_CAMS x 1..GC_ROBOTS |
| VAR | g_aiCamOwner | ARRAY[1..2] OF SINT | - | 1..GC_CAMS |
| VAR | g_astConvCfg | ARRAY[1..8] OF ST_SP_ConvCfg | - | 1..GC_FEEDS |
| VAR | g_astFeedCfg | ARRAY[1..8] OF ST_SP_TrkCfg | - | 1..GC_FEEDS |
| VAR | g_astCamCfg | ARRAY[1..2] OF ST_SP_VisionCfg | - | 1..GC_CAMS |
| VAR | g_astPatt | ARRAY[1..8] OF ST_SP_PattDef | - | 1..GC_PATT |
| VAR | g_astBatchDef | ARRAY[1..8] OF ST_SP_BatchDef | - | 1..GC_BATCHES |
| VAR | g_astRobCfg | ARRAY[1..4] OF ST_SP_RobCfg | - | 1..GC_ROBOTS |
| VAR | g_stShareCfg | ST_SP_ShareCfg | - | Load-sharing configuration mirror (recipe-loaded) |
| VAR | g_stSysCfg | ST_SP_SysCfg | - | System configuration mirror (timings, zones, flags) |
| VAR | g_aiFeedZone | ARRAY[1..8] OF SINT | - | 1..GC_FEEDS |
| VAR | g_stColCfg | ST_SP_ColCfg | - | Advanced collision guard configuration (R-05b, SP_Collision) |
| VAR | g_abConvRun | ARRAY[1..8] OF BOOL | - | 1..GC_FEEDS |
| VAR | g_stMaintCfg | ST_SP_MaintCfg | - |  |
| VAR | g_aAxisEnc | ARRAY[1..8] OF AXIS_REF | - | Conveyor encoders 1..GC_FEEDS |
| VAR | g_aGrp | ARRAY[1..4] OF AXES_GROUP_REF | - | Kinematic groups 1..GC_ROBOTS |
| VAR | g_bSim | BOOL | TRUE | TRUE = offline simulation mode |
| VAR | g_uiDtMs | UDINT | UDINT#2 |  |

**Criterio UT-G08:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G09 — `12_Application/GVL_SP_Rtc.st` — Tempo reale

**Procedura:** Verificare `stRtc` e `udiTickMs`. Atteso: tick monotono crescente a ogni ciclo del task Fast.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | g_FBRTC | Y_YA_RealTimeClock | - | Vendor RTC FB instance; called ONLY by PRG_SP_TaskSvc section 1 |
| VAR | g_stRtcNow | Yt_YA_RTC_Struct | - | Latest wall-clock snapshot (Year/Month/Day/Hour/Minute/Second/mSec) |
| VAR | g_bRtcValid | BOOL | FALSE | TRUE when the vendor RTC returned a Valid clock this cycle |
| VAR | g_uiRtcErr | UINT | UINT#0 | Last RTC FB error id (0 = none; diagnostics mirror) |
| VAR | g_sRtcNow | STRING(23) | - | Formatted snapshot 'YYYY-MM-DD HH:MM:SS.mmm' (HMI / diagnostics) |
| VAR | g_udiTickMs | UDINT | UDINT#0 | ---- Monotonic tick (duration time base) -------------------------- |

**Criterio UT-G09:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

### UT-G10 — `12_Application/GVL_SP_Sync.st` — Sincronizzazione task

**Procedura:** Verificare i contatori/handshake di scambio dati fra `PRG_SP_TaskFast` (2 ms) e `PRG_SP_TaskMain` (10 ms): `udiStatDrop` deve restare 0 per tutta la durata della campagna.

**Variabili del GVL:**

| Kind | Nome | Tipo | Init | Descrizione |
|---|---|---|---|---|
| VAR | bCfgPend | BOOL | - | TRUE = pending FB re-configure cycle |
| VAR | stPattCmd | ARRAY[1..2] OF ST_SP_PattCmd | - | One per outfeed engine |
| VAR | stPattStat | ARRAY[1..2] OF ST_SP_BatchStat | - | Copy of pattN.stStat |
| VAR | astStatEv | ARRAY[1..64] OF ST_SP_StatEv | - | Ring of pick/place/cyc |
| VAR | udiStatWr | UDINT | UDINT#0 | Producer cursor (TaskFast) |
| VAR | udiStatRd | UDINT | UDINT#0 | Consumer cursor (TaskMain) |
| VAR | udiStatDrop | UDINT | UDINT#0 | Events dropped when ring full |
| VAR | stTotPub | ST_SP_Counters | - | Copy of g_Sys.Stats.stTot |
| VAR | rPphPub | LREAL | - | Copy of g_Sys.Stats.rPiecesPerH |
| VAR | uiMainDtMs | UDINT | UDINT#10 | Period of the application task |
| VAR | uiSvcDtMs | UDINT | UDINT#100 | Period of the service task |
| VAR | bLogPend | BOOL | - | TRUE = pending log line below |
| VAR | sLogMsg | STRING(80) | - | Message text (Info level, System src) |

**Criterio UT-G10:** PASS se tutti i valori/ispezioni descritte corrispondono.

---

## Sezione 3 — Test dei 35 FUNCTION_BLOCK in isolamento (FB-T01 .. FB-T35)

Ogni FB viene testato **in isolamento**: un'istanza dedicata in `PRG_UT_Scratch`, nessuna interazione con gli altri moduli se non i mock indicati. La procedura di base:

1. Istanziare il FB in `PRG_UT_Scratch` (es. `fbX : SP_ItemQueue;`).
2. Impostare i `VAR_IN` della tabella *Setup* e chiamare il/i metodo di configurazione indicato.
3. Eseguire i passi numerati **in ordine**; dopo ogni passo attendere il numero di cicli indicato (o 1 ciclo se non indicato).
4. Confrontare ogni risultato atteso con la Watch Table dedicata.
5. Eseguire i sotto-test di fault indicati.
6. Registrare l'esito.

---

### FB-T01 — FUNCTION_BLOCK `SP_AlarmMgr` (01_Common/FB_SP_AlarmMgr.st)

**Scopo:** Gestore allarmi centralizzato (64 voci, priorità, ack)

**Inventario METHOD (7):** `ActiveCount():UINT`, `Raise():BOOL`, `Clear():BOOL`, `Ack():BOOL`, `AckAll():UINT`, `GetEntry():BOOL`, `GetActive():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | stNow | Yt_YA_RTC_Struct | - | Wall clock stamp (from TaskSvc) |
| VAR_OUTPUT | uiActive | UINT | - | Active, not yet acknowledged |
| VAR_OUTPUT | uiStored | UINT | - | Records currently in registry |
| VAR_OUTPUT | out_stAlarm | ST_SP_Alarm | - | Result buffer of GetEntry |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMax | UINT | 64 | Capacità registro |
| bEnable | BOOL | TRUE | Abilita funzionamento |

**Precondizioni:** Sistema in `Idle`, nessun allarme presente (`ActiveCount() = 0`).

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Chiamare `Raise(eSrc=ET_SP_LogSource#System, uiCode=101, uiSev=2, sMsg='Test alarm 101')` da PRG_UT_Scratch (istanza `fbAm`). | La chiamata ritorna indice voce ≥ 1; `ActiveCount() = 1`; `GetActive(1)` riporta code=101. |
| 2 | Chiamare `Raise` con uiCode=102, uiSev=3. | `ActiveCount() = 2`. |
| 3 | Leggere `GetEntry(indice)` della voce 1: verificare `uiCode=101`, `sMsg='Test alarm 101'`, `bActive=TRUE`, `bAck=FALSE`. | Dati voce corrispondenti. |
| 4 | Chiamare `Ack(indice_voce1)`. | Voce 1: `bAck=TRUE`; `uiUnack` decrementato; `bActive` invariato. |
| 5 | Chiamare `Clear(indice_voce1)` (o `Clear` con condizione di reset prevista dal FB). | Voce 1 disattivata: `ActiveCount() = 1`. |
| 6 | Chiamare `AckAll()`. | Tutte le voci residue `bAck=TRUE`; `uiUnack = 0`. |
| 7 | Saturazione: chiamare `Raise` in loop 70 volte con codici crescenti. | Nessun errore di indice fuori array; la coda rispetta `GC_ALARM_N=64` (eventuale riuso della voce più vecchia: verificare comportamento e documentarlo). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-AL1 | `Raise` con `sMsg` più lungo di `GC_STRMSG` (120). | Testo troncato senza errore di compilazione/runtime. |
| FT-AL2 | `GetEntry` con indice 0 o > 64. | Ritorno deterministico (voce vuota), nessuna eccezione. |

**Criterio FB-T01:** PASS se: conteggi corretti, ack/indipendenti da clear, nessun overflow indice.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| stNow | Yt_YA_RTC_Struct | VAR_IN | - | valore atteso dei passi |
| uiActive | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| uiStored | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_stAlarm | ST_SP_Alarm | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T02 — FUNCTION_BLOCK `SP_Logger` (01_Common/FB_SP_Logger.st)

**Scopo:** Registro eventi circolare (256 voci, export CSV)

**Inventario METHOD (7):** `Log():UDINT`, `LogInfo():UDINT`, `LogWarn():UDINT`, `LogError():UDINT`, `GetEntry():BOOL`, `ExportLine():BOOL`, `Clear():UINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | stNow | Yt_YA_RTC_Struct | - | Wall clock stamp (from TaskSvc) |
| VAR_OUTPUT | uiCount | UINT | - | Entries currently stored |
| VAR_OUTPUT | udiSeq | UDINT | - | Total entries ever logged |
| VAR_OUTPUT | out_stEntry | ST_SP_LogEntry | - | Result buffer of GetEntry/ExportLine |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMax | UINT | 256 | Capacità registro |

**Precondizioni:** `Clear()` eseguito; `stOut.uiCount = 0`.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Chiamare `LogInfo(sSrc='SYSTEM', sMsg='hello')`. | `stOut.uiCount = 1`. |
| 2 | Chiamare `LogWarn` e `LogError` con messaggi distinti. | `stOut.uiCount = 3`; `GetEntry(1..3)` restituisce le voci in ordine. |
| 3 | Verificare `ExportLine(1)` per la voce 1: confrontare la stringa CSV con formato atteso `tick;livello;sorgente;messaggio`. | Riga CSV completa e corretta. |
| 4 | Chiamare `Log` in loop 300 volte. | Nessun errore: coda circolare, `uiCount` satura a 256; la voce più vecchia viene sovrascritta. |
| 5 | Chiamare `Clear()`. | `stOut.uiCount = 0`. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-LOG1 | `GetEntry(0)` / `GetEntry(257)`. | Ritorno deterministico senza crash. |
| FT-LOG2 | `Log` con messaggio > 120 caratteri. | Troncamento sicuro. |

**Criterio FB-T02:** PASS se: ordine FIFO rispettato, export corretto, overflow gestito.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| stNow | Yt_YA_RTC_Struct | VAR_IN | - | valore atteso dei passi |
| uiCount | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| udiSeq | UDINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_stEntry | ST_SP_LogEntry | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T03 — FUNCTION_BLOCK `SP_MovAvg` (01_Common/FB_SP_MovAvg.st)

**Scopo:** Media mobile su 8 campioni (GC_MOVAVG_N)

**Inventario METHOD (0):** 

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | rIn | LREAL | - | Raw input sample |
| VAR_IN | bEnable | BOOL | - | TRUE = filter active, FALSE = bypass/reset |
| VAR_OUTPUT | rOut | LREAL | - | Filtered output |
| VAR_OUTPUT | bFilled | BOOL | - | TRUE once the window is completely filled |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| rIn | LREAL | - | Ingresso campione |
| bEnable | BOOL | TRUE | Abilita campionamento |

**Precondizioni:** FB appena istanziato (buffer vuoto).

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Impostare `rIn = 10.0` e far ciclare 8 volte. | Al campione 8: uscita media = 10.0. |
| 2 | Impostare `rIn = 20.0` per 8 cicli. | Uscita transitoria: media incrementale; dopo 8 campioni a 20: uscita = 20.0. |
| 3 | Sequenza nota: 0,8 per 8 cicli → atteso 4.0. | Uscita = 4.0 ± 0.001. |
| 4 | `bEnable = FALSE` per 5 cicli con `rIn` variabile. | Uscita invariata (campionamento sospeso). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-MA1 | Campioni alternati +V/−V per 20 cicli. | Media stabile, nessuna oscillazione anomala. |

**Criterio FB-T03:** PASS se: media esatta dopo GC_MOVAVG_N campioni e comportamento di hold con bEnable=FALSE.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| rIn | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rOut | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| bFilled | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T04 — FUNCTION_BLOCK `SP_Calib2D` (02_Geometry/FB_SP_Calib2D.st)

**Scopo:** Calibrazione 2D a 4-8 punti (pixel → mondo)

**Inventario METHOD (3):** `Reset():BOOL`, `AddPair():ET_SP_RetCode`, `Compute():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | out_stT | ST_SP_Transf2D | - | Solved transform (bValid set) |
| VAR_OUTPUT | out_rRms | LREAL | - | RMS residual [user unit] |
| VAR_OUTPUT | out_iPairs | SINT | - | Registered pairs |
| VAR_OUTPUT | out_bValid | BOOL | - | Transform usable |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_CalibCfg | - | Configurazione calibrazione |

**Precondizioni:** `Reset()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `AddPair(rPx=0, rPy=0, rWx=100, rWy=200)` ×4 coppie generatrici di una similitudine nota: (0,0)→(100,200), (1,0)→(100+2,200) con scale 2 e rot 90° come da casi UT-F28: usare le 4 coppie del pattern (0,0),(1,0),(0,1),(1,1) trasformate. | Quattro coppie accettate. |
| 2 | Chiamare `Compute()`. | Ritorno `Done`; `stOut.rDx≈100, rDy≈200, rScale≈2, rRot≈90` (tolleranza ±0.01). |
| 3 | Verifica inversa: per ogni coppia `AddPair`, `InvTrf(Trf(p)) = p` entro ±0.01. | Errore < 0.01 su tutti i punti. |
| 4 | `Reset()` poi `Compute()` senza punti. | Ritorno `ErrParam` o `ErrState` (mai crash). |
| 5 | `AddPair` con 9 punti (oltre `GC_CALIB_PTS = 8`). | Ottavo accettato, nono rifiutato senza errore fatale. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CAL1 | 3 punti allineati (matrice singolare). | `Compute` ritorna errore, non produce NaN/inf. |

**Criterio FB-T04:** PASS se: parametri stimati corretti, gestione matrice singolare sicura.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| out_stT | ST_SP_Transf2D | VAR_OUTPUT | - | valore atteso dei passi |
| out_rRms | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| out_iPairs | SINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_bValid | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T05 — FUNCTION_BLOCK `SP_ConvDrive` (03_Conveyor/FB_SP_ConvDrive.st)

**Scopo:** Interfaccia motore nastro (avanti/indietro/stop)

**Inventario METHOD (0):** 

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | Drive enable |
| VAR_IN | eMode | ET_SP_ConvDriveMode | - |  |
| VAR_IN | rFactor | LREAL | - | Requested speed factor [0..1] |
| VAR_IN | rMaxSpeed | LREAL | - | Belt speed at factor = 1 [mm/s] |
| VAR_IN | rAccel | LREAL | - | Belt acceleration [mm/s2] |
| VAR_IN | uiAnaCh | UINT | - | Analog channel index |
| VAR_OUTPUT | rCmdSpeed | LREAL | - | Commanded belt speed [mm/s] |
| VAR_IN_OUT | ioAxis | AXIS_REF | - | Belt servo axis (ServoAxis mode) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| iDir | SINT | +1 | Direzione: +1 avanti, −1 indietro, 0 stop |
| rFactor | LREAL | 1.0 | Fattore velocità |

**Precondizioni:** `stSys.bMotionPermit = TRUE`, nastro 1 in simulazione.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `iDir = +1`, `rFactor = 1.0`. | Uscite: `bFwd=TRUE, bRev=FALSE`, duty/uscita analogica = 100% del riferimento. |
| 2 | `iDir = -1`. | `bFwd=FALSE, bRev=TRUE`. |
| 3 | `iDir = 0`. | Entrambe FALSE, uscita 0. |
| 4 | `rFactor = 0.5` con `iDir = +1`. | Uscita proporzionale al 50% (se uscita analogica configurata). |
| 5 | `bEStop = TRUE` in movimento. | Uscite a 0 entro 1 ciclo del task; `bFwd/bRev=FALSE`. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CVD1 | Comandi `bFwd` e `bRev` contemporaneamente (forcing manuale delle uscite). | Interlock: mai entrambi attivi. |

**Criterio FB-T05:** PASS se: direzione corretta, stop entro 1 ciclo, interlock rispettato.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| eMode | ET_SP_ConvDriveMode | VAR_IN | - | stato/valore atteso dei passi |
| rFactor | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rMaxSpeed | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rAccel | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| uiAnaCh | UINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| rCmdSpeed | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| ioAxis | AXIS_REF | VAR_IN_OUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T06 — FUNCTION_BLOCK `SP_ConvEncoder` (03_Conveyor/FB_SP_ConvEncoder.st)

**Scopo:** Encoder nastro (posizione e velocità)

**Inventario METHOD (0):** 

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | TRUE = acquire position this cycle |
| VAR_IN | bSim | BOOL | - | TRUE = simulated position source |
| VAR_IN | rSimPos | LREAL | - | Simulated belt position [mm] |
| VAR_OUTPUT | rPos | LREAL | - | Belt position [encoder units -> scaled] |
| VAR_OUTPUT | bValid | BOOL | - | Position valid this cycle |
| VAR_IN_OUT | ioAxis | AXIS_REF | - | Encoder / belt axis (firmware binding) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| bSim | BOOL | TRUE | Simulazione tacche |
| rBeltSpeed | LREAL | 450.0 | Velocità simulata mm/s |

**Precondizioni:** Encoder azzerato.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Attivare `bSim` con velocità 450 mm/s per 1 s (100 cicli da 10 ms). | Posizione avanzata di ≈450 mm (±1%); velocità stimata ≈450 mm/s. |
| 2 | Portare velocità a 0. | Velocità stimata decade a 0; posizione ferma. |
| 3 | Segno negativo (nastro indietro a −200 mm/s). | Posizione decresce; velocità ≈ −200. |
| 4 | Confronto con `GVL_SP_Rtc.udiTickMs`: 10 s a 450 mm/s. | Incremento posizione ≈ 4500 mm (±1%). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-ENC1 | Rumore: ±1 tacca improvvisa. | Filtro velocità evita picchi; stima continua. |

**Criterio FB-T06:** PASS se: integrazione della velocità coerente entro ±1%.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bSim | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rSimPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rPos | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| bValid | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| ioAxis | AXIS_REF | VAR_IN_OUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T07 — FUNCTION_BLOCK `SP_Conveyor` (03_Conveyor/FB_SP_Conveyor.st)

**Scopo:** Nastro completo: pacing automatico, finestre, fattori

**Inventario METHOD (3):** `Configure():ET_SP_RetCode`, `FactorFor():LREAL`, `InWindow():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | Master enable (system running) |
| VAR_IN | rNearDist | LREAL | - | Nearest item distance upstream of pick line [mm]; GC_REAL_MAX when none |
| VAR_IN | rDtSec | LREAL | - | Task period [s] |
| VAR_IN | bSim | BOOL | - | Simulated conveyor |
| VAR_IN | rSimPos | LREAL | - | Simulated belt position [mm] |
| VAR_IN | rSimFrc | LREAL | - | Simulated speed factor override (scenario) |
| VAR_IN_OUT | ioAxis | AXIS_REF | - | Encoder / belt axis |
| VAR_OUTPUT | stOut | ST_SP_ConvStat | - | Published status (HMI + system) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.rSlowAhead | LREAL | 250.0 | Distanza rallentamento |
| stCfg.rStopAhead | LREAL | 80.0 | Distanza arresto |
| stCfg.rSpeedMax | LREAL | 1200.0 | Velocità massima |

**Precondizioni:** `Configure()` chiamato; coda tracking con pezzi noti.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `Configure()` con i valori della tabella. | `stOut.bConfigured = TRUE`. |
| 2 | `FactorFor(rNearest = 600.0)` (nessuna zona di influsso). | Ritorno = 1.0 (velocità piena). |
| 3 | `FactorFor(rNearest = 250.0)` (esattamente rSlowAhead). | Ritorno = 1.0 (nessun rallentamento ancora). |
| 4 | `FactorFor(rNearest = 165.0)` (metà strada fra 250 e 80). | Ritorno = 0.5 ± 0.01 (interpolazione lineare). |
| 5 | `FactorFor(rNearest = 80.0)`. | Ritorno = 0.0 (arresto). |
| 6 | `FactorFor(rNearest = 20.0)` (oltre la soglia). | Ritorno = 0.0 (mantenuto). |
| 7 | `InWindow(rPos=1000, rFrom=900, rTo=1100)`. | TRUE — dentro la finestra. |
| 8 | `InWindow(rPos=899.9, rFrom=900, rTo=1100)`. | FALSE — prima della finestra. |
| 9 | Dinamica: simulare pezzo che entra a 600 mm e avanza; osservare `rReqFactor` su WT_2. | Fattore decresce linearmente da 1.0 a 0.0 fra 250 e 80 mm. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CONV1 | Pezzi multipli a distanze diverse. | Factor = minimo sui pezzi presenti (verificare). |
| FT-CONV2 | `rSpeedMax` = 0. | Nessuna divisione per zero; fattore limitato. |

**Criterio FB-T07:** PASS se: curve di pacing rispettate al centesimo, finestre esatte.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rNearDist | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rDtSec | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| bSim | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rSimPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rSimFrc | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| ioAxis | AXIS_REF | VAR_IN_OUT | - | valore atteso dei passi |
| stOut | ST_SP_ConvStat | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T08 — FUNCTION_BLOCK `SP_DrvAscii` (04_Vision/FB_SP_DrvAscii.st)

**Scopo:** Driver camera ASCII/CSV (parsing risposta e item)

**Inventario METHOD (7):** `BuildTrig():STRING(64)`, `RespComplete():BOOL`, `m_ParseLine():BOOL`, `m_ParseFields():BOOL`, `GetItem():BOOL`, `ClearItems():UDINT`, `Configure():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | TRUE = driver operational |
| VAR_IN | bTrig | BOOL | - | Rising edge = image trigger |
| VAR_IN | udiTickMs | UDINT | - | Monotonic ms tick (GVL_SP_Rtc, v1.8.0) |
| VAR_IN | rBeltPos | LREAL | - | Belt position at trigger [mm] (stamping) |
| VAR_OUTPUT | eState | ET_SP_VisionState | - | Driver lifecycle state (Offline/Connecting/Online/Triggered) |
| VAR_OUTPUT | bDone | BOOL | - | One-cycle pulse: image fully processed |
| VAR_OUTPUT | bErr | BOOL | - | Protocol/communication error pulse |
| VAR_OUTPUT | uiErr | UINT | - | Error code: 1=open,2=timeout,3=send,4=parse |
| VAR_OUTPUT | bItemsAvail | BOOL | - | Parsed items waiting for GetItem |
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | Current item for GetItem |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMaxItems | UINT | 8 | Item per scatto |

**Precondizioni:** `Configure()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Simulare riga di risposta nota: `ITEM,1250.0,340.5,90.0,0.98,1` (formato atteso dal driver: verificare il parser `m_ParseLine`). | `GetItem(1)` restituisce le coordinate/score/tipo attesi. |
| 2 | Riga con campi mancanti. | Voce ignorata o default sicuri; nessun crash. |
| 3 | Riga con numero decimale con virgola (es. 1.234,5). | Rifiutata o gestita in modo deterministico (documentare). |
| 4 | `ClearItems()` poi `GetItem(1)`. | Nessun item (ritorno vuoto/`bValid=FALSE`). |
| 5 | `BuildTrig(...)`: verificare la stringa di trigger costruita. | Stringa formattata come da protocollo ASCII del costruttore. |
| 6 | `RespComplete` con buffer parziale. | `FALSE` finché il terminatore non arriva. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-DRV1 | Riga di 300 caratteri. | Gestione lunghezza senza overflow. |
| FT-DRV2 | Risposta di 100 item con `uiMaxItems=8`. | Primi 8 accettati, resto scartato con conteggio. |

**Criterio FB-T08:** PASS se: parsing esatto, robustezza su input malformati.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bTrig | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| rBeltPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| eState | ET_SP_VisionState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bItemsAvail | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T09 — FUNCTION_BLOCK `SP_DrvCognex` (04_Vision/FB_SP_DrvCognex.st)

**Scopo:** Driver Cognex (dati in formato Cognex)

**Inventario METHOD (3):** `Configure():ET_SP_RetCode`, `GetItem():BOOL`, `ClearItems():UDINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | TRUE = driver operational (forwarded to engine) |
| VAR_IN | bTrig | BOOL | - | Image trigger (rising edge, forwarded) |
| VAR_IN | udiTickMs | UDINT | - | Time source (forwarded) |
| VAR_IN | rBeltPos | LREAL | - | Belt position at trigger [mm] (stamped into items) |
| VAR_OUTPUT | eState | ET_SP_VisionState | - | Engine state passthrough |
| VAR_OUTPUT | bDone | BOOL | - | Image-processed pulse passthrough |
| VAR_OUTPUT | bErr | BOOL | - | Error pulse passthrough |
| VAR_OUTPUT | uiErr | UINT | - | Error code passthrough (1=open 2=timeout 3=send 4=parse) |
| VAR_OUTPUT | bItemsAvail | BOOL | - | Items ready for GetItem passthrough |
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | GetItem result passthrough |
| VAR_OUTPUT | stCfg | ST_SP_VisionCfg | - | Public config passthrough |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMaxItems | UINT | 8 | Item per scatto |

**Precondizioni:** `Configure()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Inserire payload Cognex di esempio (campo job/registro nota). | `GetItem(1)` con coordinate e score attesi. |
| 2 | `ClearItems()`. | Buffer vuoto. |
| 3 | Verificare che `Configure` imponga porta 5000 se `uiPort=0` (via `FUN_SP_CamPreset`). | Porta 5000. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CGX1 | Payload troncato a metà. | Scarto sicuro, nessun item spurio. |

**Criterio FB-T09:** PASS se: mapping campi corretto e robustezza.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bTrig | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| rBeltPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| eState | ET_SP_VisionState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bItemsAvail | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |
| stCfg | ST_SP_VisionCfg | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T10 — FUNCTION_BLOCK `SP_DrvGeneric` (04_Vision/FB_SP_DrvGeneric.st)

**Scopo:** Driver TCP generico

**Inventario METHOD (3):** `Configure():ET_SP_RetCode`, `GetItem():BOOL`, `ClearItems():UDINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | TRUE = driver operational (forwarded to engine) |
| VAR_IN | bTrig | BOOL | - | Image trigger (rising edge, forwarded) |
| VAR_IN | udiTickMs | UDINT | - | Time source (forwarded) |
| VAR_IN | rBeltPos | LREAL | - | Belt position at trigger [mm] (stamped into items) |
| VAR_OUTPUT | eState | ET_SP_VisionState | - | Engine state passthrough |
| VAR_OUTPUT | bDone | BOOL | - | Image-processed pulse passthrough |
| VAR_OUTPUT | bErr | BOOL | - | Error pulse passthrough |
| VAR_OUTPUT | uiErr | UINT | - | Error code passthrough (1=open 2=timeout 3=send 4=parse) |
| VAR_OUTPUT | bItemsAvail | BOOL | - | Items ready for GetItem passthrough |
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | GetItem result passthrough |
| VAR_OUTPUT | stCfg | ST_SP_VisionCfg | - | Public config passthrough |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMaxItems | UINT | 8 | Item per scatto |

**Precondizioni:** `Configure()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Payload CSV generico `x,y,th,score`. | `GetItem(1)` atteso. |
| 2 | Verificare porta default 10001. | Porta 10001. |
| 3 | `ClearItems()`. | Buffer vuoto. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-GEN1 | Payload vuoto. | Nessun item, nessun errore fatale. |

**Criterio FB-T10:** PASS se: parsing base e default porta corretti.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bTrig | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| rBeltPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| eState | ET_SP_VisionState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bItemsAvail | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |
| stCfg | ST_SP_VisionCfg | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T11 — FUNCTION_BLOCK `SP_DrvKeyence` (04_Vision/FB_SP_DrvKeyence.st)

**Scopo:** Driver Keyence

**Inventario METHOD (3):** `Configure():ET_SP_RetCode`, `GetItem():BOOL`, `ClearItems():UDINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | TRUE = driver operational (forwarded to engine) |
| VAR_IN | bTrig | BOOL | - | Image trigger (rising edge, forwarded) |
| VAR_IN | udiTickMs | UDINT | - | Time source (forwarded) |
| VAR_IN | rBeltPos | LREAL | - | Belt position at trigger [mm] (stamped into items) |
| VAR_OUTPUT | eState | ET_SP_VisionState | - | Engine state passthrough |
| VAR_OUTPUT | bDone | BOOL | - | Image-processed pulse passthrough |
| VAR_OUTPUT | bErr | BOOL | - | Error pulse passthrough |
| VAR_OUTPUT | uiErr | UINT | - | Error code passthrough (1=open 2=timeout 3=send 4=parse) |
| VAR_OUTPUT | bItemsAvail | BOOL | - | Items ready for GetItem passthrough |
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | GetItem result passthrough |
| VAR_OUTPUT | stCfg | ST_SP_VisionCfg | - | Public config passthrough |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMaxItems | UINT | 8 | Item per scatto |

**Precondizioni:** `Configure()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Payload Keyence di esempio. | `GetItem(1)` atteso. |
| 2 | `ClearItems()`. | Buffer vuoto. |
| 3 | Verificare porta default 8888 con `uiPort=0`. | Porta 8888. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-KEY1 | Payload con separatore anomalo. | Scarto sicuro. |

**Criterio FB-T11:** PASS se: mapping e default porta corretti.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bTrig | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| rBeltPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| eState | ET_SP_VisionState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bItemsAvail | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |
| stCfg | ST_SP_VisionCfg | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T12 — FUNCTION_BLOCK `SP_Socket` (04_Vision/FB_SP_Socket.st)

**Scopo:** Canale socket (RX buffer, overflow)

**Inventario METHOD (4):** `PollRx():BOOL`, `TakeRx():BOOL`, `RxCount():UINT`, `RxOverflow():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bOpen | BOOL | - | TRUE = connection desired |
| VAR_IN | sHost | STRING(16) | - | Remote IP |
| VAR_IN | uiPort | UINT | - | Remote port |
| VAR_IN | sTx | STRING(128) | - | Payload to transmit |
| VAR_IN | bSend | BOOL | - | Rising edge: transmit sTx |
| VAR_IN | tTimeout | TIME | - | Connection timeout |
| VAR_IN | udiTickMs | UDINT | - | Monotonic ms tick (GVL_SP_Rtc, v1.8.0) |
| VAR_OUTPUT | eState | ET_SP_SocketState | - | Socket lifecycle (Closed/Connecting/Connected/Fault) |
| VAR_OUTPUT | bConn | BOOL | - | TRUE when Connected |
| VAR_OUTPUT | uiErr | UINT | - | Last socket error code |
| VAR_OUTPUT | out_sRx | STRING(255) | - | Drained payload (filled by TakeRx) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.uiMaxRx | UINT | 256 | Buffer ricezione |

**Precondizioni:** Socket in simulazione o loopback.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Inviare 10 frame di prova. | `RxCount() = 10`; `TakeRx()` restituisce i frame in ordine FIFO. |
| 2 | Dopo ogni `TakeRx()`. | `RxCount()` decrementa. |
| 3 | Inviare 300 frame senza leggere. | `RxOverflow()` diventa TRUE; buffer limitato a `uiMaxRx` senza crash. |
| 4 | Svuotare con `TakeRx` fino a 0. | `RxCount() = 0`; `TakeRx` su buffer vuoto è sicuro. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-SOCK1 | Frame da 0 byte. | Scartato senza bloccare la coda. |
| FT-SOCK2 | `PollRx` con socket chiuso. | Nessun blocco del task (timeout interno). |

**Criterio FB-T12:** PASS se: FIFO corretta, overflow marcato, nessun blocco.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bOpen | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| sHost | STRING(16) | VAR_IN | '' | testo atteso dei passi |
| uiPort | UINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| sTx | STRING(128) | VAR_IN | '' | testo atteso dei passi |
| bSend | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| tTimeout | TIME | VAR_IN | - | valore atteso dei passi |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| eState | ET_SP_SocketState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| bConn | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_sRx | STRING(255) | VAR_OUTPUT | '' | testo atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T13 — FUNCTION_BLOCK `SP_VisionCam` (04_Vision/FB_SP_VisionCam.st)

**Scopo:** Camera completa: policy, trigger, harvesting, item

**Inventario METHOD (8):** `ResetPolicy():BOOL`, `PolicyEngine():BOOL`, `Fire():BOOL`, `HarvestFromDrv():SINT`, `GetNextItem():BOOL`, `InjectItem():ET_SP_RetCode`, `TriggerNow():BOOL`, `Configure():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | Camera enabled by system |
| VAR_IN | rBeltPos | LREAL | - | Belt position (reference conveyor) [mm] |
| VAR_IN | rBeltSpeed | LREAL | - | Signed belt speed [mm/s] |
| VAR_IN | bExtTrig | BOOL | - | External trigger input (edge) |
| VAR_IN | rDtSec | LREAL | - | Task period [s] |
| VAR_IN | udiTickMs | UDINT | - | Monotonic ms tick (GVL_SP_Rtc) |
| VAR_IN | abiFeedFree | ARRAY[1..8] OF BOOL | - | TRUE = feed queue has space 1..GC_FEEDS |
| VAR_OUTPUT | stOut | ST_SP_VisionStat | - | Published status |
| VAR_OUTPUT | out_iFeed | SINT | - | Feed tag of the drained item |
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | Drained item (with assigned id) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.eDrv | ET_SP_VisionDrv | Simulated | Driver |
| stCfg.tTimeout | TIME | T#800ms | Timeout scatto |
| stCfg.tDelay | TIME | T#40ms | Trigger delay |
| stCfg.uiMaxItems | UINT | 8 | Max item/scatto |
| stCfg.rMinScore | LREAL | 0.5 | Soglia qualità |

**Precondizioni:** `Configure()` eseguito; `ResetPolicy()` chiamato.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `TriggerNow()`. | `stOut.bBusy = TRUE` fino allo scatto simulato; poi `stOut.uiItems ≥ 1` e `stOut.bValid = TRUE`. |
| 2 | `InjectItem(stItem)` con score 0.9 e coordinate note. | `GetNextItem()` restituisce l'item con le coordinate iniettate. |
| 3 | `InjectItem` con score 0.3 (< rMinScore). | Item scartato dalla policy; `uiItems` invariato. |
| 4 | `HarvestFromDrv()` dopo uno scatto del simulatore con 3 item. | 3 item catturati rispettando `uiMaxItems`. |
| 5 | `PolicyEngine()` in ciclo: attivare priorità/timeout definiti nella configurazione. | Le transizioni di stato della policy seguono i timeout (`tTimeout`, `tInterval`). |
| 6 | Nessuna risposta entro `tTimeout`. | `stOut.bTimeout = TRUE`, allarme camera tramite `SP_AlarmMgr` (verificare voce). |
| 7 | `Fire()` con `bEnable=FALSE` della camera. | Nessuno scatto; stato coerente. |
| 8 | Conteggio: 10 scatti validi. | `stOut.udiScatti = 10` (o contatori equivalenti del FB). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CAM1 | Timeout ripetuti ×5. | Allarmi ripetuti ma sistema non si blocca; contatore timeout incrementa. |
| FT-CAM2 | Scatto con 20 item e `uiMaxItems=8`. | Primi 8 accettati; `udiOverflow` documentato. |

**Criterio FB-T13:** PASS se: trigger→harvest→item coerenti, policy e timeout rispettati.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rBeltPos | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rBeltSpeed | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| bExtTrig | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rDtSec | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| udiTickMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| abiFeedFree | ARRAY[1..8] OF BOOL | VAR_IN | - | valore atteso dei passi |
| stOut | ST_SP_VisionStat | VAR_OUTPUT | - | valore atteso dei passi |
| out_iFeed | SINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T14 — FUNCTION_BLOCK `SP_ItemQueue` (05_Tracking/FB_SP_ItemQueue.st)

**Scopo:** Coda tracking pezzi — con filtro doppioni multi-foto

**Inventario METHOD (16):** `PublishCounts():BOOL`, `Configure():ET_SP_RetCode`, `FindDuplicate():SINT`, `Add():ET_SP_RetCode`, `ItemOffset():LREAL`, `Reserve():ET_SP_RetCode`, `ReserveCluster():ET_SP_RetCode`, `Release():ET_SP_RetCode`, `CompletePick():ET_SP_RetCode`, `GetItem():BOOL`, `SetPlaced():ET_SP_RetCode`, `NearDist():BOOL`, `Housekeeping():ET_SP_RetCode`, `AgeItems():BOOL`, `ClearAll():UINT`, `AddRaw():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | uiTracked | UINT | - | Items in state Tracked |
| VAR_OUTPUT | uiReserved | UINT | - | Items in state Reserved |
| VAR_OUTPUT | out_stItem | ST_SP_TrkItem | - | Result buffer of GetItem |
| VAR_OUTPUT | out_rNear | LREAL | - | Result buffer of NearDist [mm] |
| VAR_OUTPUT | out_stRes | ST_SP_ResRsp | - | Result buffer of Reserve |
| VAR_OUTPUT | out_stCl | ST_SP_ClRsp | - | Result buffer of ReserveCluster (R-07) |
| VAR_OUTPUT | out_uiPurged | UINT | - | Result buffer of Housekeeping (total) |
| VAR_OUTPUT | out_uiPurgedFlow | UINT | - | Housekeeping: lost/timed-out items |
| VAR_OUTPUT | out_uiPurgedTerm | UINT | - | Housekeeping: closed picks/placements |
| VAR_OUTPUT | out_bDup | BOOL | - | TRUE when Add merged/suppressed a duplicate item |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg.rDupTol | LREAL | 25.0 | Tolleranza doppione mm |
| stCfg.rAgeMs | UDINT | 60000 | Età scadenza pezzo |
| stCfg.rWinBehind | LREAL | 20.0 | Finestra dietro il sensore |

**Precondizioni:** `Configure()` eseguito, `ClearAll()` chiamato: `stOut.uiTracked=0, udiDup=0`.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| TK-01 | **Doppione multi-foto (core feature)**: `FeedItem` pezzo A con `rEncCap=1000.0, rX=500, rY=0, rTh=10, iTyp=1`. Dopo 10 cicli, secondo `FeedItem` dello stesso pezzo visto a `rEncCap=1200.0` (nastro avanzato) e `rX=500` (stessa traiettoria): stima velocità = (1200-1000)/Δt = 253 mm/s. | **Atteso:** `stOut.uiTracked` resta **1**, `stOut.udiFed` resta **1**, `stOut.udiDup` diventa **1**; la posa del pezzo viene aggiornata con la foto più recente (ID invariato). |
| TK-02 | **Doppione con pezzo già riservato**: riservare il pezzo (`Reserve`) verso un robot, poi `FeedItem` di un doppione entro 25 mm. | **Atteso:** nessun nuovo pezzo in coda (`uiTracked` invariato); `udiDup` incrementa; la riserva esistente NON viene alterata. |
| TK-03 | **Due pezzi veri**: `FeedItem` di due pezzi distanti 40 mm (> `GC_DUP_TOL_MM`). | **Atteso:** `uiTracked = 2`, `udiDup` invariato. |
| TK-04 | **Tolleranza**: due pezzi distanti 24 mm (< 25 mm) nello stesso istante. | **Atteso:** considerati doppioni: `uiTracked = 1`, `udiDup = 1` (documentare se il merge usa la foto più recente). |
| TK-05 | **Proiezione temporale**: doppione con velocità stimata non nulla: `ItemOffset` deve proiettare il pezzo esistente a `rEncCap` del nuovo campione prima di misurare la distanza (2D belt distance). | Distanza calcolata sulla proiezione: verifica con numeri del Caso TK-01. |
| TK-06 | `Reserve(uiId, iRob)` su pezzo tracciato. | Stato → `Reserved`; `stOut.udiRes` incrementa; `GetItem` restituisce il robot assegnato. |
| TK-07 | `ReserveCluster` con 2 item sincronizzati (coppia nota, `rEncCap` allineato con `SyncPickPending`/`CompSyncPickTargets` lato robot). | Entrambi riservati; valori di `rEncCap` allineati fra i due item. |
| TK-08 | `Release(uiId)` su pezzo riservato. | Torna `Tracked`; `udiRes` decrementa. |
| TK-09 | `CompletePick(uiId)` su pezzo riservato. | Stato `Picked`; `udiPick` incrementa. |
| TK-10 | `SetPlaced(uiId)` su pezzo `Picked`. | Stato `Placed`; esce dai conteggi attivi. |
| TK-11 | `NearDist(rPos)` con pezzi a 100, 300, 700 mm. | Ritorno = 100 mm (il più vicino). |
| TK-12 | `Housekeeping()` dopo `GC_ITEM_AGE_MS` di inattività. | Pezzi scaduti rimossi; `uiTracked` decrementa. |
| TK-13 | `AgeItems()` con pezzo vecchio. | Età aggiornata; scadenza gestita. |
| TK-14 | **Pause/Resume**: mettere `bPause=TRUE` e alimentare item. | Item accodati ma non riservabili; alla ripresa, ordinati correttamente. |
| TK-15 | Saturazione: 70 `FeedItem` distinti. | Massimo `GC_QUEUE=64` item; il 65° viene rifiutato con `eRc=ErrFull` (nessun crash). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-ITQ1 | `FeedItem` con `rX/rY` NaN o enormi (1e12). | Scartato o clippato; coda coerente. |
| FT-ITQ2 | `Reserve` su ID inesistente. | `eRc=ErrNotFound`, nessun side-effect. |
| FT-ITQ3 | `Reserve` su pezzo già `Picked`. | `eRc=ErrState` (stato non valido). |

**Criterio FB-T14:** PASS se: tutti i 15 casi corrispondono — **in particolare TK-01..TK-04 (anti-doppioni)**.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiTracked | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| uiReserved | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_stItem | ST_SP_TrkItem | VAR_OUTPUT | - | valore atteso dei passi |
| out_rNear | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| out_stRes | ST_SP_ResRsp | VAR_OUTPUT | - | valore atteso dei passi |
| out_stCl | ST_SP_ClRsp | VAR_OUTPUT | - | valore atteso dei passi |
| out_uiPurged | UINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_uiPurgedFlow | UINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_uiPurgedTerm | UINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_bDup | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T15 — FUNCTION_BLOCK `SP_TrkFeed` (05_Tracking/FB_SP_TrkFeed.st)

**Scopo:** Front-end tracking: feed item, target di posa, deleghe

**Inventario METHOD (11):** `Configure():ET_SP_RetCode`, `FeedItem():ET_SP_RetCode`, `AddTarget():ET_SP_RetCode`, `Reserve():ET_SP_RetCode`, `ReserveCluster():ET_SP_RetCode`, `CompletePick():ET_SP_RetCode`, `Release():ET_SP_RetCode`, `PlaceTarget():ET_SP_RetCode`, `NearDist():BOOL`, `Housekeeping():BOOL`, `ResetAll():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | stOut | ST_SP_TrkStat | - | Published statistics |
| VAR_OUTPUT | out_stRes | ST_SP_ResRsp | - | Reservation result buffer |
| VAR_OUTPUT | out_stCl | ST_SP_ClRsp | - | Cluster reservation result buffer (R-07) |
| VAR_OUTPUT | out_rNear | LREAL | - | Nearest item distance [mm] |
| VAR_OUTPUT | bNearFound | BOOL | - | TRUE when an item is in flow |

**Precondizioni:** `Configure()` eseguito; `ResetAll()` chiamato.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `FeedItem(...)` con i parametri di TK-01. | Delega a `SP_ItemQueue.Add`: stessi risultati di TK-01. |
| 2 | `AddTarget(...)` con target di posa su vassoio. | Target accodato; `GetNextTarget` lo restituisce. |
| 3 | `Reserve`/`ReserveCluster`/`Release`/`CompletePick`. | Comportamento identico a `SP_ItemQueue` (delega). |
| 4 | `PlaceTarget(...)` dopo la posa. | Target aggiornato; `NotifyPlaced` correlato. |
| 5 | `NearDist(...)` e `Housekeeping()`. | Come `SP_ItemQueue`. |
| 6 | `ResetAll()`. | Code vuote, contatori azzerati. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-TRK1 | `FeedItem` in parallelo da due camere nello stesso ciclo. | Entrambi gli item gestiti senza perdita (verificare `udiFed`). |

**Criterio FB-T15:** PASS se: la delega preserva tutti i comportamenti di `SP_ItemQueue`.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| stOut | ST_SP_TrkStat | VAR_OUTPUT | - | valore atteso dei passi |
| out_stRes | ST_SP_ResRsp | VAR_OUTPUT | - | valore atteso dei passi |
| out_stCl | ST_SP_ClRsp | VAR_OUTPUT | - | valore atteso dei passi |
| out_rNear | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| bNearFound | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T16 — FUNCTION_BLOCK `SP_BatchMgr` (06_Pattern/FB_SP_BatchMgr.st)

**Scopo:** Gestione batch (8 batch, 4 livelli, mix tipi)

**Inventario METHOD (11):** `CountActive():UINT`, `AddBatch():SINT`, `SetBatch():ET_SP_RetCode`, `StartBatch():ET_SP_RetCode`, `StopBatch():ET_SP_RetCode`, `GetActive():SINT`, `GetDef():BOOL`, `GetStat():BOOL`, `GetId():UDINT`, `SyncProgress():BOOL`, `ClearAll():UINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | uiActive | UINT | - | Number of running batches |
| VAR_OUTPUT | out_stDef | ST_SP_BatchDef | - | Result buffer of GetDef |
| VAR_OUTPUT | out_stStat | ST_SP_BatchStat | - | Result buffer of GetStat |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stDef | ST_SP_BatchDef | - | Definizione batch |

**Precondizioni:** `ClearAll()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `AddBatch(stDef)` con 3 battute, 2 livelli. | Ritorno ID batch ≥ 1; `CountActive() = 1`. |
| 2 | `StartBatch(id)`. | `GetStat(id)` → `bRunning=TRUE`. |
| 3 | `SyncProgress(id, uiDone=1)` ×3. | Al termine: `stStat.bComplete=TRUE`; `uiDone=3`. |
| 4 | `StopBatch(id)` su batch avviato. | Stato → fermato; progresso conservato. |
| 5 | `GetActive()` con 3 batch attivi. | Restituisce il primo attivo secondo l'ordinamento del FB. |
| 6 | `SetBatch` per aggiornare una definizione. | `GetDef` riflette il cambiamento. |
| 7 | Saturazione: 10 `AddBatch`. | Max `GC_BATCHES=8`; il 9° rifiutato con errore esplicito. |
| 8 | Progressione multi-livello: batch con 2 livelli × 4 file. | Al termine del livello 1 passa al livello 2 (verificare `iLayer`); al termine totale, batch completo. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-BAT1 | `SyncProgress` con uiDone > battute previste. | Saturazione al massimo; `bComplete=TRUE`. |
| FT-BAT2 | `StartBatch` su ID inesistente. | `ErrNotFound`. |

**Criterio FB-T16:** PASS se: lifecycle completo, saturazione gestita, multi-livello corretto.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiActive | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_stDef | ST_SP_BatchDef | VAR_OUTPUT | - | valore atteso dei passi |
| out_stStat | ST_SP_BatchStat | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T17 — FUNCTION_BLOCK `SP_PatternGen` (06_Pattern/FB_SP_PatternGen.st)

**Scopo:** Generatore pattern di posa (8 pattern × 16 slot, multi-layer)

**Inventario METHOD (10):** `Configure():ET_SP_RetCode`, `StartBatch():ET_SP_RetCode`, `AbortBatch():BOOL`, `OnSensor():BOOL`, `Engine():BOOL`, `NewTray():BOOL`, `MixType():UINT`, `PushTarget():ET_SP_RetCode`, `GetNextTarget():BOOL`, `NotifyPlaced():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | bActive | BOOL | - | Generating (batch running) |
| VAR_OUTPUT | out_stTarget | ST_SP_TrkItem | - | Drained target (GetNextTarget) |
| VAR_OUTPUT | uiGenPending | UINT | - | Targets waiting for drain |
| VAR_OUTPUT | stStat | ST_SP_BatchStat | - | Runtime batch state |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_PattCfg | - | Configurazione pattern |

**Precondizioni:** `Configure()` eseguito; nessun batch attivo.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `StartBatch` con pattern 3×2, 1 livello. | Target generati in ordine: verificare coordinate con `GetNextTarget` (6 target). |
| 2 | `NotifyPlaced()` dopo ogni posa. | Il target corrente avanza; dopo 6, batch completo. |
| 3 | `OnSensor()` (fronte sensore vassoio) con modalità sensore. | `NewTray()` genera un nuovo piano di posa. |
| 4 | `MixType(...)` con 2 tipi di prodotto nel batch. | Gli slot vengono assegnati ai tipi secondo la sequenza del mix. |
| 5 | `AbortBatch()` a metà. | Generazione fermata; stato ripulito. |
| 6 | Batch multi-livello (2 livelli). | Al termine del livello 1, `Engine` genera il livello 2 (offset Z o avanzamento battuta). |
| 7 | `PushTarget`/`GetNextTarget` in loop. | FIFO coerente; nessun target perso. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-PAT1 | `OnSensor` doppio fronte in un ciclo. | Un solo `NewTray` (anti-rimbalzo). |
| FT-PAT2 | Pattern con 0 slot. | `StartBatch` rifiutato (`ErrParam`). |

**Criterio FB-T17:** PASS se: generazione ordinata, sensori anti-rimbalzo, multi-livello corretto.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bActive | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_stTarget | ST_SP_TrkItem | VAR_OUTPUT | - | valore atteso dei passi |
| uiGenPending | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| stStat | ST_SP_BatchStat | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T18 — FUNCTION_BLOCK `SP_LoadBalancer` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Scopo:** Distribuzione carico 4 robot (Organic/Greedy/Balanced/Manual)

**Inventario METHOD (7):** `Configure():ET_SP_RetCode`, `Eligible():BOOL`, `OfferProduct():SINT`, `m_Organic():SINT`, `m_Greedy():SINT`, `m_Balanced():SINT`, `m_Manual():SINT`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | out_rBestScore | LREAL | - | Score of the chosen robot (diagnostic) |
| VAR_OUTPUT | out_iEligible | SINT | - | Number of eligible robots (diagnostic) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| eStrat | ET_SP_Strategy | — | Organic/Greedy/Balanced/Manual |
| astRob[].bUsed | BOOL | TRUE | Robot disponibili |

**Precondizioni:** `Configure()` eseguito; 4 robot in stato `Ready`.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `Eligible(iRob)` per robot abilitato/disabilitato. | TRUE/False coerenti con `bUsed` e stato. |
| 2 | Strategia `Greedy`: offrire 10 pezzi. | Il pezzo va sempre al robot più vicino (verificare assegnazione con `NearDist`). |
| 3 | Strategia `Balanced`: offrire 12 pezzi con i robot a conteggi diversi. | Gli assegnamenti pareggiano i conteggi di pick (±1). |
| 4 | Strategia `Organic`: offrire pezzi con i robot che si muovono. | Assegnamento per prossimità dinamica (nessun round-robin forzato). |
| 5 | Strategia `Manual`: offrire pezzo con mappa manuale impostata. | Segue la mappa manuale. |
| 6 | `OfferProduct` con tutti i robot occupati. | Ritorno: nessuna assegnazione (`ErrBusy` o equivalente). |
| 7 | `OfferProduct` con 1 solo robot `Ready`. | Tutti i pezzi a quel robot. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-LB1 | Robot in fault escluso. | Non riceve offerte finché non ripristinato. |
| FT-LB2 | Due `OfferProduct` nello stesso ciclo. | Entrambi gestiti senza perdita. |

**Criterio FB-T18:** PASS se: le 4 strategie rispettano le rispettive regole di assegnazione.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| out_rBestScore | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| out_iEligible | SINT | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T19 — FUNCTION_BLOCK `SP_ZoneGuard` (07_LoadSharing/FB_SP_ZoneGuard.st)

**Scopo:** Guardia zone di lavoro (4 zone, richiesta/rilascio)

**Inventario METHOD (1):** `Configure():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | FALSE = all grants TRUE |
| VAR_IN | abRobReq | ARRAY[1..4] OF BOOL | - | Robot requests its feed zone 1..GC_ROBOTS |
| VAR_IN | aiRobFeed | ARRAY[1..4] OF SINT | - | Feed each robot works on 1..GC_ROBOTS |
| VAR_OUTPUT | abGrant | ARRAY[1..4] OF BOOL | - | TRUE = robot free to move 1..GC_ROBOTS |
| VAR_OUTPUT | abHold | ARRAY[1..4] OF BOOL | - | Latched grant (diagnostic) 1..GC_ROBOTS |
| VAR_OUTPUT | auiCnt | ARRAY[1..4] OF UINT | - | Current holders per zone 1..GC_ZONES |
| VAR_OUTPUT | uiWait | UINT | - | Robots waiting for a zone |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_ZoneCfg | - | Mappa zone |

**Precondizioni:** `Configure()` eseguito; tutte le zone libere.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `Request` robot 1 su zona 1. | `bOccupied[1] = TRUE`; ritorno `Done`. |
| 2 | `Request` robot 2 su zona 1. | Ritorno `Busy`/`ErrState` (zona occupata). |
| 3 | `Release` robot 1. | Zona libera; robot 2 può entrare. |
| 4 | `Request` robot 1 su zona 0 (`GC_ZONE_NONE`). | Sempre consentito (nessuna zona). |
| 5 | `Request` su 2 zone simultanee. | Seconda richiesta negata finché la prima non è rilasciata. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-ZG1 | `Release` senza `Request` precedente. | Nessun errore fatale; stato invariato. |
| FT-ZG2 | `Request` con indice robot invalido. | `ErrParam`. |

**Criterio FB-T19:** PASS se: mutua esclusione perfetta e nessun deadlock fra zone.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| abRobReq | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| aiRobFeed | ARRAY[1..4] OF SINT | VAR_IN | - | valore atteso dei passi |
| abGrant | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abHold | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| auiCnt | ARRAY[1..4] OF UINT | VAR_OUTPUT | - | valore atteso dei passi |
| uiWait | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T20 — FUNCTION_BLOCK `SP_RobMotion` (08_Robot/FB_SP_RobMotion.st)

**Scopo:** Simulatore dinamica robot (corpo mobile per test collisioni)

**Inventario METHOD (1):** `SimBody():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bSim | BOOL | - | TRUE = kinematic simulation, no FW |
| VAR_IN | bEnable | BOOL | - | Group enable command |
| VAR_IN | bStopReq | BOOL | - | Controlled stop request |
| VAR_IN | bReset | BOOL | - | Fault reset request |
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | udiSeq | UDINT | - | Request sequence counter |
| VAR_IN | eMv | ET_SP_MvKind | - | Move kind |
| VAR_IN | stTarget | ST_SP_Pose3D | - | Target pose WORLD/MCS [mm, rad] |
| VAR_IN | rVel | LREAL | - | Path velocity [mm/s] |
| VAR_IN | rAcc | LREAL | - | Acceleration [mm/s2] |
| VAR_IN | rDec | LREAL | - | Deceleration [mm/s2] |
| VAR_IN | rZone | LREAL | - | Corner zone radius [mm] (precision mode) |
| VAR_IN | rBeltSpd | LREAL | - | Belt speed for tracked moves [mm/s] (fallback diagnostics) |
| VAR_IN | stTargetBelt | ST_SP_Pose3D | - | Target of the armed move in the BELT CS/PCS [mm, rad] |
| VAR_IN | stBeltOrg | ST_SP_Pose3D | - | Belt CS origin in MCS, x-axis along belt travel |
| VAR_IN | stObjBelt | ST_SP_Pose3D | - | Product pose in the belt CS at capture (session anchor) |
| VAR_IN | rSyncDist | LREAL | - | TrackOptions.SyncIn.ConveyorDistance [mm], > 0 |
| VAR_IN | bTrkReq | BOOL | - |  |
| VAR_IN | bFwReadyIn | BOOL | - | Real group enabled/ready status |
| VAR_IN | bFwRefIn | BOOL | - | Real group referenced/homed status |
| VAR_OUTPUT | bEnabled | BOOL | - | Group enabled |
| VAR_OUTPUT | bHomed | BOOL | - | Group ready (referenced) |
| VAR_OUTPUT | bBusy | BOOL | - | Move in progress |
| VAR_OUTPUT | bDone | BOOL | - | One-cycle pulse: move finished |
| VAR_OUTPUT | bErr | BOOL | - | Move error pulse |
| VAR_OUTPUT | uiErrId | UINT | - | Error id (1 robot layer, 201/202 tracking session) |
| VAR_OUTPUT | p2Now | ST_SP_Pose2D | - | Current world pose [mm, rad] |
| VAR_OUTPUT | rZNow | LREAL | - | Current Z [mm] |
| VAR_OUTPUT | bTrkSess | BOOL | - | FW-1: tracking session open or releasing |
| VAR_OUTPUT | bTrkInSync | BOOL | - | FW-1: group synchronized with the belt (Active) |
| VAR_IN_OUT | ioGrp | AXES_GROUP_REF | - | Firmware kinematic group |
| VAR_IN_OUT | ioBelt | AXIS_REF | - | FW-1: conveyor belt encoder axis (per pick feed) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_RobMotionCfg | - | Dinamica simulata |

**Precondizioni:** Simulatore inizializzato a posizione nota.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Comandare moto a velocità costante verso un target noto. | Posizione interpolata linearmente; tempo di percorrenza = distanza/velocità. |
| 2 | Osservare `SimBody` in ciclo. | Posa TCP aggiornata ogni ciclo senza salti. |
| 3 | Comandare stop. | Ferma entro 1 ciclo con decelerazione definita. |
| 4 | Due simulatori avvicinati sotto `SepSlow`. | Il simulatore rispetta il rallentamento imposto da `SP_Collision`. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-RM1 | Target coincidente con posizione attuale. | Nessuna oscillazione; stato `Done`. |

**Criterio FB-T20:** PASS se: cinematica simulata coerente con le leggi di moto impostate.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bSim | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bStopReq | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bReset | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| udiSeq | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| eMv | ET_SP_MvKind | VAR_IN | - | stato/valore atteso dei passi |
| stTarget | ST_SP_Pose3D | VAR_IN | - | valore atteso dei passi |
| rVel | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rAcc | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rDec | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rZone | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rBeltSpd | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| stTargetBelt | ST_SP_Pose3D | VAR_IN | - | valore atteso dei passi |
| stBeltOrg | ST_SP_Pose3D | VAR_IN | - | valore atteso dei passi |
| stObjBelt | ST_SP_Pose3D | VAR_IN | - | valore atteso dei passi |
| rSyncDist | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| bTrkReq | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bFwReadyIn | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bFwRefIn | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bEnabled | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bHomed | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bBusy | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiErrId | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| p2Now | ST_SP_Pose2D | VAR_OUTPUT | - | valore atteso dei passi |
| rZNow | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| bTrkSess | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bTrkInSync | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| ioGrp | AXES_GROUP_REF | VAR_IN_OUT | - | valore atteso dei passi |
| ioBelt | AXIS_REF | VAR_IN_OUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T21 — FUNCTION_BLOCK `SP_Robot` (08_Robot/FB_SP_Robot.st)

**Scopo:** FB Robot completo (FSM, job, tracking, cluster, fault)

**Inventario METHOD (26):** `Configure():ET_SP_RetCode`, `OfferJob():BOOL`, `CancelJob():BOOL`, `MarkFault():BOOL`, `ClearFault():BOOL`, `EnterFault():BOOL`, `SetBeltFrames():ET_SP_RetCode`, `CompBeltTargets():BOOL`, `MvToBelt():BOOL`, `LatchCmds():BOOL`, `MvTo():BOOL`, `CupPose():ST_SP_Pose3D`, `LoadOff():BOOL`, `CompPickTargets():BOOL`, `CompPlaceTargets():BOOL`, `AdvancePickItem():BOOL`, `AdvancePlaceItem():BOOL`, `CloseJob():BOOL`, `CompSyncPickTargets():BOOL`, `CompSyncPlaceTargets():BOOL`, `SyncPickPending():BOOL`, `SyncPlaceTry():BOOL`, `CupHolding():BOOL`, `Fsm():BOOL`, `FirstFailedPlace():SINT`, `Publish():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bSysRun | BOOL | - | System running (production allowed) |
| VAR_IN | bSim | BOOL | - | Simulated kinematics |
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bFwReady | BOOL | - | Real group ready status |
| VAR_IN | bFwRef | BOOL | - | Real group referenced status |
| VAR_IN | bZoneOk | BOOL | TRUE | FALSE freezes the active job (zone hold) |
| VAR_IN | rVelScale | LREAL | 1.0 | R-05b collision guard: live velocity scale [0.1..1], 1.0 = full speed |
| VAR_IN | stCmd | ST_SP_RobCmd | - | Public command struct (System/HMI writes) |
| VAR_IN_OUT | ioGrp | AXES_GROUP_REF | - | Firmware kinematic group |
| VAR_IN_OUT | ioaBelt | ARRAY[1..8] OF AXIS_REF | - | FW-1: belt encoder axes, one per feed (native tracking) 1..GC_FEEDS |
| VAR_OUTPUT | stOut | ST_SP_RobStat | - | Published status (HMI + balancer) |
| VAR_OUTPUT | bJobDone | BOOL | - | One-cycle pulse: job finished |
| VAR_OUTPUT | m_stJobRes | ST_SP_Job | - | Result copy (System reads after bJobDone) |
| VAR_OUTPUT | stCfg | ST_SP_RobCfg | - | Configuration |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_RobCfg | via `FUN_SP_RobCfgDefault` | Configurazione robot |
| iRob | SINT | 1 | Indice robot |
| eMode | ET_SP_Mode | Simulated | Simulated/Auto/Service |

**Precondizioni:** `Configure()` eseguito; `SetBeltFrames()` chiamato con i frame nastro reali (o di simulazione).

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `OfferJob(job)` con pezzo a 1000 mm e target fisso. | Stato FSM: `Offert→Pick`; il robot accetta il job. |
| 2 | Ciclo di prenda standard (`Fsm` in ciclo). | Sequenza: MoveToPick → Approach → GripStart → Retreat; `stOut.udiPick` incrementa al termine. |
| 3 | `CompPickTargets`: con 2 ventose e 2 item. | I due target sono costruiti rispetto al TCP e alla posa dei cup (`CupPose`). |
| 4 | **Cluster sincronizzato**: `OfferJob` con `bCluster=TRUE` e 2 item. | `CompSyncPickTargets` allinea i due item sullo stesso `rEncCap`; la prenda avviene in un solo passaggio. |
| 5 | `CompPlaceTargets` su vassoio 2×2. | Le posa rispetta la sequenza degli slot. |
| 6 | **Tracking nativo** (`MvToBelt`, `MC_TrackConveyorBelt` in simulazione): prenda su nastro a 450 mm/s. | Il target si aggiorna durante l'avvicinamento; errore di inseguimento < 2 mm simulati. |
| 7 | `AdvancePickItem`/`AdvancePlaceItem` durante il ciclo. | Le code avanzano coerentemente ai completamenti. |
| 8 | `CloseJob` al termine. | Job chiuso; `stOut.uiCycleMs` aggiornato. |
| 9 | **GripEval (fallimento parziale)**: forzare `stFbk` con una ventosa vuota dopo `GripStart`. | Il job passa a monopezzo: `FirstFailedPlace` identifica la ventosa vuota; la posa procede per la ventosa carica. |
| 10 | `CancelJob` durante la prenda. | Job annullato; pezzo rilasciato in coda (`Release`); stato coerente. |
| 11 | `MarkFault`/`ClearFault`. | Stato `Fault`; nessun movimento possibile; dopo `ClearFault` ritorno a `Ready`. |
| 12 | `EnterFault` per allarme esterno. | Come `MarkFault` con motivo registrato. |
| 13 | `SetBeltFrames` con nuovi offset. | `CompBeltTargets` riflette l'aggiornamento. |
| 14 | `LoadOff` dopo la posa. | `stOut.bHolding[*] = FALSE`; conteggi aggiornati. |
| 15 | `Publish()` ogni ciclo. | `stOut` aggiornato su GVL per le WT. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-RB1 | Presa a vuoto completa (nessun fbk). | Retry fino a `iRetries`; poi item scartato/messo in errore con allarme. |
| FT-RB2 | Timeout di inseguimento nastro. | Job annullato in sicurezza; `udiAbortFlight` incrementa. |
| FT-RB3 | `OfferJob` con coda vuota. | `ErrEmpty`. |

**Criterio FB-T21:** PASS se: FSM completa, cluster e tracking corretti, gestione fallimenti deterministica.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bSysRun | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bSim | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bFwReady | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bFwRef | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bZoneOk | BOOL | VAR_IN | TRUE | transizioni attese secondo i passi |
| rVelScale | LREAL | VAR_IN | 1.0 | valore atteso dei passi (±0.001) |
| stCmd | ST_SP_RobCmd | VAR_IN | - | valore atteso dei passi |
| ioGrp | AXES_GROUP_REF | VAR_IN_OUT | - | valore atteso dei passi |
| ioaBelt | ARRAY[1..8] OF AXIS_REF | VAR_IN_OUT | - | valore atteso dei passi |
| stOut | ST_SP_RobStat | VAR_OUTPUT | - | valore atteso dei passi |
| bJobDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| m_stJobRes | ST_SP_Job | VAR_OUTPUT | - | valore atteso dei passi |
| stCfg | ST_SP_RobCfg | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T22 — FUNCTION_BLOCK `SP_ToolCtl` (08_Robot/FB_SP_ToolCtl.st)

**Scopo:** Controllo attrezzo: valvole, ventose, feedback

**Inventario METHOD (17):** `Configure():ET_SP_RetCode`, `AutoCh():UINT`, `ChPick():UINT`, `ChPlace():UINT`, `ChFbk():UINT`, `WritePick():BOOL`, `WritePlace():BOOL`, `FbkOk():BOOL`, `GripStart():ET_SP_RetCode`, `GripSync():ET_SP_RetCode`, `PlaceStart():ET_SP_RetCode`, `AbortAll():BOOL`, `RefreshFbk():BOOL`, `FbkCup():BOOL`, `CaptureCups():BOOL`, `HoldingOf():BOOL`, `ResetCounters():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bInhibit | BOOL | - | TRUE = dry-run: outputs forced OFF |
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_OUTPUT | astStat | ARRAY[1..4] OF ST_SP_ToolStat | - | Per-tool status published to HMI 1..GC_TOOLS |
| VAR_OUTPUT | bAnyBusy | BOOL | - | Any grip/release sequence running |
| VAR_OUTPUT | bDone | BOOL | - | One-cycle pulse: sequence finished |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_ToolCfg | - | Config attrezzo |

**Precondizioni:** `Configure()` eseguito; `ResetCounters()` chiamato.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `ChPick(1)` / `ChPlace(1)` con `WritePick`/`WritePlace`. | Uscite valvole corrette sul canale impostato. |
| 2 | `GripStart` con 2 ventose. | `GripSync` attiva entrambe le ventose in sincrono. |
| 3 | `FbkOk` con pressione sufficiente. | `TRUE`; `FbkCup` riporta stato per ventosa. |
| 4 | `PlaceStart` con blow-off. | Uscita blow attiva per `tRelease`; poi OFF. |
| 5 | `AutoCh` con selezione automatica canale. | Canale scelto coerentemente con il job corrente. |
| 6 | `CaptureCups` dopo la prenda. | Stato ventose catturato in `HoldingOf`. |
| 7 | `AbortAll` in movimento. | Tutte le valvole OFF entro 1 ciclo. |
| 8 | `RefreshFbk` ciclico. | Feedback aggiornato ogni ciclo del task. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-TL1 | Feedback ventosa assente dopo `tGrip`. | =FALSE su `FbkOk` per quel cup; segnalato a `SP_Robot` per GripEval. |
| FT-TL2 | Comando valvole con canale fuori range. | `ErrParam`, nessuna uscita scambiata. |

**Criterio FB-T22:** PASS se: tempi valvola rispettati, feedback per-ventosa corretto, abort sicuro.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bInhibit | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| astStat | ARRAY[1..4] OF ST_SP_ToolStat | VAR_OUTPUT | - | valore atteso dei passi |
| bAnyBusy | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bDone | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T23 — FUNCTION_BLOCK `SP_Dispatch` (09_Production/FB_SP_Dispatch.st)

**Scopo:** Dispatcher lavoro → robot (stati 0..N, store item)

**Inventario METHOD (6):** `Configure():ET_SP_RetCode`, `Run():BOOL`, `StepRobot():BOOL`, `StoreItem():BOOL`, `Abandon():BOOL`, `ResetAll():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | stShare | ST_SP_ShareCfg | - | Distribution configuration |
| VAR_IN | aiOutfeed | ARRAY[1..8] OF SINT | - | mirror of stShare.aiOutfeedMap 1..GC_FEEDS |
| VAR_IN | abiFeedOn | ARRAY[1..8] OF BOOL | - | Feed eligible for dispatch 1..GC_FEEDS |
| VAR_IN | bEnable | BOOL | - | System dispatch gate |
| VAR_IN | uiMaxGrip | UINT | UINT#1 | Parts per cycle |
| VAR_IN | abSyncGrip | ARRAY[1..4] OF BOOL | - |  |
| VAR_IN | astReq | ARRAY[1..4] OF ST_SP_DispReq | - | Handshake responses and latched request flags (Main/Fast access) 1..GC_ROBOTS |
| VAR_IN | abReqPulse | ARRAY[1..4] OF BOOL | - |  |
| VAR_IN | astResRsp | ARRAY[1..4] OF ST_SP_ResRsp | - | Fast fills |
| VAR_IN | abResDone | ARRAY[1..4] OF BOOL | - | Fast fills |
| VAR_IN | astClRsp | ARRAY[1..4] OF ST_SP_ClRsp | - | Fast fills |
| VAR_IN | ajobOffer | ARRAY[1..4] OF ST_SP_Job | - | Completed job offers per robot |
| VAR_IN | abJobPulse | ARRAY[1..4] OF BOOL | - |  |
| VAR_IN | astJobRes | ARRAY[1..4] OF ST_SP_Job | - | Fast fills |
| VAR_IN | abJobResDone | ARRAY[1..4] OF BOOL | - | Fast fills |
| VAR_IN | astCancel | ARRAY[1..4] OF ST_SP_CancelReq | - |  |
| VAR_IN | abCancelPulse | ARRAY[1..4] OF BOOL | - |  |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_DispCfg | - | Configurazione dispatcher |

**Precondizioni:** `Configure()` eseguito; `ResetAll()` chiamato.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `Run()` con 1 pezzo e 1 robot pronto. | Il pezzo viene offerto al robot; `StoreItem` registra l'associazione job-item. |
| 2 | `StepRobot(1)` passo-passo. | Le transizioni di stato del dispatcher avanzano di un passo per chiamata (verificare gli stati). |
| 3 | Due pezzi e due robot. | Entrambi i job vengono emessi nello stesso ciclo (nessun tick perso). |
| 4 | `Abandon(job)` su job attivo. | Job annullato; item restituito alla coda. |
| 5 | `ResetAll()`. | Stato dispatcher azzerato. |
| 6 | **Verifica handover**: tempo fra fine `Retreat` del ciclo N e offerta del ciclo N+1. | ≤ 2 cicli del task Main (20 ms) — baseline per la feature BM-08 (Zero-Tick Handover). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-DSP1 | `Run` con robot tutti occupati. | Il pezzo resta in coda; nessuna perdita. |
| FT-DSP2 | `StepRobot` con indice invalido. | `ErrParam`. |

**Criterio FB-T23:** PASS se: dispatch senza perdite, handover ≤ 20 ms misurato.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| stShare | ST_SP_ShareCfg | VAR_IN | - | valore atteso dei passi |
| aiOutfeed | ARRAY[1..8] OF SINT | VAR_IN | - | valore atteso dei passi |
| abiFeedOn | ARRAY[1..8] OF BOOL | VAR_IN | - | valore atteso dei passi |
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| uiMaxGrip | UINT | VAR_IN | UINT#1 | incrementa coerentemente agli stimoli |
| abSyncGrip | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| astReq | ARRAY[1..4] OF ST_SP_DispReq | VAR_IN | - | valore atteso dei passi |
| abReqPulse | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| astResRsp | ARRAY[1..4] OF ST_SP_ResRsp | VAR_IN | - | valore atteso dei passi |
| abResDone | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| astClRsp | ARRAY[1..4] OF ST_SP_ClRsp | VAR_IN | - | valore atteso dei passi |
| ajobOffer | ARRAY[1..4] OF ST_SP_Job | VAR_IN | - | valore atteso dei passi |
| abJobPulse | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| astJobRes | ARRAY[1..4] OF ST_SP_Job | VAR_IN | - | valore atteso dei passi |
| abJobResDone | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |
| astCancel | ARRAY[1..4] OF ST_SP_CancelReq | VAR_IN | - | valore atteso dei passi |
| abCancelPulse | ARRAY[1..4] OF BOOL | VAR_IN | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T24 — FUNCTION_BLOCK `SP_Stats` (09_Production/FB_SP_Stats.st)

**Scopo:** Statistiche di produzione (pick/place/cicli/allarmi)

**Inventario METHOD (6):** `AddPick():BOOL`, `AddPlace():BOOL`, `AddCycle():BOOL`, `AddAlarm():BOOL`, `GetFeed():BOOL`, `Reset():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bProd | BOOL | - | TRUE while producing (uptime accrual) |
| VAR_OUTPUT | stTot | ST_SP_Counters | - | System totals |
| VAR_OUTPUT | out_stCnt | ST_SP_Counters | - | Result buffer of GetFeed |
| VAR_OUTPUT | udiUptimeMs | UDINT | - | Production uptime [ms] |
| VAR_OUTPUT | rPiecesPerH | LREAL | - | Estimated pieces/hour (rolling) |

**Precondizioni:** `Reset()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `AddPick(1)` ×5. | `GetFeed`/contatori: pick = 5. |
| 2 | `AddPlace(1)` ×4. | place = 4; scarto logico = 1. |
| 3 | `AddCycle(120)` ×10. | Media ciclo = 120 ms. |
| 4 | `AddAlarm()` ×2. | Contatore allarmi = 2. |
| 5 | `Reset()`. | Tutti i contatori a 0. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-ST1 | `AddCycle` con valore 0. | Accettato senza corrompere la media. |

**Criterio FB-T24:** PASS se: conteggi e medie corretti.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bProd | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| stTot | ST_SP_Counters | VAR_OUTPUT | - | valore atteso dei passi |
| out_stCnt | ST_SP_Counters | VAR_OUTPUT | - | valore atteso dei passi |
| udiUptimeMs | UDINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| rPiecesPerH | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T25 — FUNCTION_BLOCK `SP_System` (09_Production/FB_SP_System.st)

**Scopo:** Orchestrazione sistema: FSM, batch, perdita robot

**Inventario METHOD (13):** `Step():BOOL`, `StageOutputs():BOOL`, `BatchService():BOOL`, `SetBatch():ET_SP_RetCode`, `GetBatchDef():BOOL`, `GetBatchStat():BOOL`, `GetActiveBatch():SINT`, `SyncBatchProgress():BOOL`, `AddPickStat():BOOL`, `AddPlaceStat():BOOL`, `AddCycleStat():BOOL`, `OnRobotLoss():BOOL`, `Publish():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bEStopOk | BOOL | - | Safety chain OK |
| VAR_IN | stSysCfg | ST_SP_SysCfg | - | Public configuration & commands (Main/HMI write) |
| VAR_IN | stCmd | ST_SP_SysCmd | - | Operator/System command register (start, stop, batch...) |
| VAR_IN | aiPattStart | ARRAY[1..8] OF SINT | - | Batch start/abort pulses per outfeed 1..GC_FEEDS (set by BatchService, cleared by Main) |
| VAR_IN | aiPattAbort | ARRAY[1..8] OF SINT | - |  |
| VAR_OUTPUT | stOut | ST_SP_SysStat | - | Published system status |
| VAR_OUTPUT | abCamEnable | ARRAY[1..2] OF BOOL | - | 1..GC_CAMS |
| VAR_OUTPUT | abConvEnable | ARRAY[1..8] OF BOOL | - | Conveyor enable vector staged by startup state 1..GC_FEEDS |
| VAR_OUTPUT | abDispatchOn | BOOL | - | Dispatcher enable output (final stage) |
| VAR_OUTPUT | abRobPause | ARRAY[1..4] OF BOOL | - | Pause command per robot 1..GC_ROBOTS |
| VAR_OUTPUT | abRobResume | ARRAY[1..4] OF BOOL | - | Resume command per robot 1..GC_ROBOTS |
| VAR_OUTPUT | abRobReset | ARRAY[1..4] OF BOOL | - | Fault-reset command per robot 1..GC_ROBOTS |
| VAR_OUTPUT | abRobDryRun | ARRAY[1..4] OF BOOL | - | Dry-run command per robot 1..GC_ROBOTS |
| VAR_OUTPUT | bClearItemsPulse | BOOL | - | One-cycle pulse requesting queue purge on all tracking feeds |
| VAR_OUTPUT | stTot | ST_SP_Counters | - | Published statistics mirrors from subordinate Stats |
| VAR_OUTPUT | rPiecesPerH | LREAL | - |  |
| VAR_OUTPUT | udiUptimeMs | UDINT | - |  |
| VAR_OUTPUT | out_stBatchDef | ST_SP_BatchDef | - | Batch query buffers from subordinate Batch |
| VAR_OUTPUT | out_stBatchStat | ST_SP_BatchStat | - |  |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_SysCfg | - | Configurazione sistema |

**Precondizioni:** `Idle`, `eMode=Simulated`.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `bStart=TRUE` da WT_1. | FSM: `Idle → Running`; `bMotionPermit=TRUE`. |
| 2 | `Step()` ciclico. | `StageOutputs` aggiorna gli output di sistema ogni ciclo. |
| 3 | `SetBatch`/`GetBatchDef`/`GetBatchStat`/`GetActiveBatch`. | Delega coerente a `SP_BatchMgr` (verificare con Sez. FB_SP_BatchMgr). |
| 4 | `AddPickStat`/`AddPlaceStat`/`AddCycleStat`. | Delega a `SP_Stats`. |
| 5 | `OnRobotLoss(1)` con `bResilience=TRUE` e 1 robot attivo. | Il carico/camere del robot 1 vengono migrati; `stSys.udiAbortFlight` documentato; sistema NON va in blocco totale. |
| 6 | `bStop=TRUE`. | FSM: `Running → Stopping → Idle` a fine ciclo. |
| 7 | `bEStop=TRUE` in Running. | FSM → `Emergency`; `bMotionPermit=FALSE` entro 1 ciclo. |
| 8 | `bReset=TRUE` da Emergency (E-Stop rilasciato). | FSM → `Idle`; contatori di allarme mantenuti finché non ack. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-SYS1 | `bStart` e `bStop` simultanei. | Priorità deterministica (documentata), stato coerente. |
| FT-SYS2 | Perdita 2 robot insieme. | Con `bResilience=TRUE` il sistema continua con i robot residui; con `FALSE` → `Emergency`. |

**Criterio FB-T25:** PASS se: FSM completa, resilienza verificata, sicurezza E-Stop entro 1 ciclo.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bEStopOk | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| stSysCfg | ST_SP_SysCfg | VAR_IN | - | valore atteso dei passi |
| stCmd | ST_SP_SysCmd | VAR_IN | - | valore atteso dei passi |
| aiPattStart | ARRAY[1..8] OF SINT | VAR_IN | - | valore atteso dei passi |
| aiPattAbort | ARRAY[1..8] OF SINT | VAR_IN | - | valore atteso dei passi |
| stOut | ST_SP_SysStat | VAR_OUTPUT | - | valore atteso dei passi |
| abCamEnable | ARRAY[1..2] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abConvEnable | ARRAY[1..8] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abDispatchOn | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| abRobPause | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abRobResume | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abRobReset | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| abRobDryRun | ARRAY[1..4] OF BOOL | VAR_OUTPUT | - | valore atteso dei passi |
| bClearItemsPulse | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| stTot | ST_SP_Counters | VAR_OUTPUT | - | valore atteso dei passi |
| rPiecesPerH | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| udiUptimeMs | UDINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| out_stBatchDef | ST_SP_BatchDef | VAR_OUTPUT | - | valore atteso dei passi |
| out_stBatchStat | ST_SP_BatchStat | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T26 — FUNCTION_BLOCK `SP_FileIo` (10_Persistence/FB_SP_FileIo.st)

**Scopo:** I/O file (scrittura/lettura riga per riga)

**Inventario METHOD (5):** `OpenWrite():BOOL`, `OpenRead():BOOL`, `WriteLine():BOOL`, `CloseNow():BOOL`, `ReadStep():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bCloseReq | BOOL | - | TRUE = close the open file |
| VAR_OUTPUT | eState | ET_SP_FileState | - | File operation lifecycle (Idle/Reading/Writing/Done/Error) |
| VAR_OUTPUT | uiErr | UINT | - | Last file error code (firmware / adapter specific) |
| VAR_OUTPUT | bLineRdy | BOOL | - | A line is available in out_sLine |
| VAR_OUTPUT | out_sLine | STRING(200) | - | Last read line |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| sName | STRING | 'test.csv' | Nome file |

**Precondizioni:** File assente.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `OpenWrite('test.csv')`. | Ritorno `Done`. |
| 2 | `WriteLine('riga1')`, `WriteLine('riga2')`. | Due righe scritte. |
| 3 | `CloseNow()`. | File chiuso e flushato. |
| 4 | `OpenRead('test.csv')` + `ReadStep` ×2. | `riga1`, `riga2` lette in ordine; terzo `ReadStep` → `ErrEmpty`/EOF. |
| 5 | `OpenWrite` su file già aperto. | Secondo `OpenWrite` rifiutato o chiude e riapre (documentare). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-FIO1 | `OpenRead` file inesistente. | `ErrNotFound`/`ErrIo`, nessun crash. |
| FT-FIO2 | `WriteLine` senza `OpenWrite`. | `ErrState`. |

**Criterio FB-T26:** PASS se: round-trip file corretto, errori gestiti.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bCloseReq | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| eState | ET_SP_FileState | VAR_OUTPUT | - | stato/valore atteso dei passi |
| uiErr | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bLineRdy | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_sLine | STRING(200) | VAR_OUTPUT | '' | testo atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T27 — FUNCTION_BLOCK `SP_RecipeMgr` (10_Persistence/FB_SP_RecipeMgr.st)

**Scopo:** Ricette: export/import CSV completo

**Inventario METHOD (13):** `ExportBegin():BOOL`, `ExportNext():BOOL`, `ExpConv():BOOL`, `ExpFeed():BOOL`, `ExpCam():BOOL`, `ExpCamMap():BOOL`, `ExpPatt():BOOL`, `ExpBatch():BOOL`, `ExpBatchMix():BOOL`, `ExpShare():BOOL`, `ExpShareR():BOOL`, `ImportLine():BOOL`, `GetError():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | out_sLine | STRING(200) | - | Export: line to write |
| VAR_OUTPUT | uiProgress | UINT | - | Export row counter (diagnostic) |
| VAR_OUTPUT | bErr | BOOL | - | Last import line rejected |
| VAR_OUTPUT | sName | STRING(32) | - | Recipe name |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| sPath | STRING | 'recipe.csv' | Percorso |

**Precondizioni:** Configurazione di default caricata (`FUN_SP_RobCfgDefault` + valori di fabbrica).

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `ExportBegin('recipe.csv')`. | File creato; riga di intestazione presente. |
| 2 | `ExportNext` in loop fino a `ErrEmpty`/`Done` definitivo. | Il file contiene le sezioni: Conv, Feed, Cam, CamMap, Patt, Batch, BatchMix, Share, ShareR (metodi `ExpConv`…`ExpShareR`). |
| 3 | Modificare 3 parametri in memoria (es. `rSlowAhead`, `rDupTol` config, `tTimeout` cam). | Valori aggiornati nelle istanze. |
| 4 | `ImportLine` su ogni riga del file esportato. | I parametri tornano ai valori originali; `GetError()` = nessun errore. |
| 5 | `ImportLine` con riga corrotta (`CONV;x;y`). | `GetError()` riporta numero riga; i parametri validi precedenti restano applicati. |
| 6 | Round-trip: esportare, importare, riesportare. | I due file sono identici (verifica con diff del PC). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-RCP1 | File con valori numerici non validi. | Default applicati; errore riportato. |
| FT-RCP2 | Import con file vuoto. | Nessuna modifica alla configurazione. |

**Criterio FB-T27:** PASS se: round-trip identico, gestione errori con numero riga.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| out_sLine | STRING(200) | VAR_OUTPUT | '' | testo atteso dei passi |
| uiProgress | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |
| bErr | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| sName | STRING(32) | VAR_OUTPUT | '' | testo atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T28 — FUNCTION_BLOCK `SP_RetainMgr` (10_Persistence/FB_SP_RetainMgr.st)

**Scopo:** Persistenza e checksum configurazione

**Inventario METHOD (5):** `Validate():BOOL`, `RestoreDefaults():BOOL`, `ChkSum():UDINT`, `SaveNow():BOOL`, `SetRecipe():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | bRestored | BOOL | - | TRUE = valid retain data available |
| VAR_OUTPUT | bDefaults | BOOL | - | TRUE = blob was invalid, defaults applied |
| VAR_OUTPUT | uiVer | UINT | - |  |

**Precondizioni:** Configurazione nota.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `ChkSum()` sulla configurazione corrente. | Valore stabile e ripetibile (2 chiamate = stesso valore). |
| 2 | Modificare un parametro; `ChkSum()`. | Checksum cambiato. |
| 3 | `Validate()`. | `TRUE` con checksum coerente; `FALSE` se la memoria è corrotta (forcing di un campo). |
| 4 | `SaveNow()`. | Dati salvati; dopo restart simulato, `RestoreDefaults` + `SetRecipe` ripristinano lo stato. |
| 5 | `RestoreDefaults()`. | Tutti i parametri ai valori di fabbrica; `ChkSum` coerente. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-RET1 | Corruzione simulata di un campo (forcing). | `Validate() = FALSE`; ripristino da backup. |

**Criterio FB-T28:** PASS se: checksum reattivo, ripristino verificato.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bRestored | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| bDefaults | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| uiVer | UINT | VAR_OUTPUT | 0 | incrementa coerentemente agli stimoli |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T29 — FUNCTION_BLOCK `SP_SimCamera` (11_Simulation/FB_SP_SimCamera.st)

**Scopo:** Simulatore camera (spawn pezzi, casualità controllata)

**Inventario METHOD (3):** `SpawnBatch():UINT`, `GetNextItem():BOOL`, `Rand():LREAL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | out_stItem | ST_SP_VisionItem | - | Drained item (GetNextItem) |
| VAR_OUTPUT | stVi | ST_SP_VisionItem | - | Last generated item |
| VAR_IN | bEnable | BOOL | - | Scenario active |
| VAR_IN | iCam | SINT | - | Target camera index 1..GC_CAMS |
| VAR_IN | iFeed | SINT | - | Target feed index 1..GC_FEEDS |
| VAR_IN | rEncNow | LREAL | - | Belt encoder [mm] |
| VAR_IN | rTrigDist | LREAL | 200.0 | Spawn distance [mm] |
| VAR_IN | uiItemsPerImg | UINT | 3 | Items per image (1..GC_VIS_MAX) |
| VAR_IN | uiTypeMin | UINT | 1 | Type mix lower bound |
| VAR_IN | uiTypeMax | UINT | 4 | Type mix upper bound |
| VAR_IN | rXmin | LREAL | -80.0 | Across-belt span [mm] |
| VAR_IN | rXmax | LREAL | 80.0 |  |
| VAR_IN | rVmin | LREAL | 60.0 | Upstream offset span [mm] |
| VAR_IN | rVmax | LREAL | 300.0 |  |
| VAR_IN | rBeltZ | LREAL | 0.0 | Belt surface Z (world) |
| VAR_IN | uiDtMs | UDINT | - |  |
| VAR_IN | bTrigExt | BOOL | - | External spawn request (edge) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_SimCamCfg | - | Configurazione simulatore |

**Precondizioni:** Simulatore attivo.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `SpawnBatch` con 4 pezzi. | `GetNextItem` restituisce 4 item con pose plausibili. |
| 2 | `Rand()` in loop 100 volte. | Valori nell'intervallo atteso, nessuna ripetizione patologica. |
| 3 | `GetNextItem` a buffer vuoto. | Ritorno sicuro (`bValid=FALSE`). |
| 4 | Simulazione overlap: due pezzi entro 25 mm. | Il simulatore li genera come due foto dello stesso pezzo (per test anti-doppioni TK-01). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-SC1 | `SpawnBatch` con 0 pezzi. | Nessun item; nessun errore. |

**Criterio FB-T29:** PASS se: riproducibilità dei test TK-* garantita.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| out_stItem | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |
| stVi | ST_SP_VisionItem | VAR_OUTPUT | - | valore atteso dei passi |
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| iCam | SINT | VAR_IN | - | valore atteso dei passi |
| iFeed | SINT | VAR_IN | - | valore atteso dei passi |
| rEncNow | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rTrigDist | LREAL | VAR_IN | 200.0 | valore atteso dei passi (±0.001) |
| uiItemsPerImg | UINT | VAR_IN | 3 | incrementa coerentemente agli stimoli |
| uiTypeMin | UINT | VAR_IN | 1 | incrementa coerentemente agli stimoli |
| uiTypeMax | UINT | VAR_IN | 4 | incrementa coerentemente agli stimoli |
| rXmin | LREAL | VAR_IN | -80.0 | valore atteso dei passi (±0.001) |
| rXmax | LREAL | VAR_IN | 80.0 | valore atteso dei passi (±0.001) |
| rVmin | LREAL | VAR_IN | 60.0 | valore atteso dei passi (±0.001) |
| rVmax | LREAL | VAR_IN | 300.0 | valore atteso dei passi (±0.001) |
| rBeltZ | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bTrigExt | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T30 — FUNCTION_BLOCK `SP_SimConveyor` (11_Simulation/FB_SP_SimConveyor.st)

**Scopo:** Simulatore nastro (integrazione velocità → posizione)

**Inventario METHOD (0):** 

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bRun | BOOL | - | Belt running |
| VAR_IN | rSetSpd | LREAL | - | Set speed [mm/s] |
| VAR_IN | rFactor | LREAL | - | Slow/stop factor [0..1] |
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bReset | BOOL | - | Position reset (start of test) |
| VAR_OUTPUT | rPos | LREAL | - | Virtual belt position [mm] |
| VAR_OUTPUT | rSpeed | LREAL | - | Virtual belt speed [mm/s] |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_SimConvCfg | - | Configurazione |

**Precondizioni:** Simulatore attivo.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Velocità 450 mm/s per 10 s. | Posizione ≈ 4500 mm (±1%). |
| 2 | Velocità variabile a rampa. | Posizione = integrale della velocità (verifica grafico/WT). |
| 3 | Rapporto con `SP_ConvEncoder`. | Le stime sono coerenti fra loro (±1%). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-SCV1 | Velocità negativa. | Movimento indietro corretto. |

**Criterio FB-T30:** PASS se: integrazione coerente entro ±1%.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bRun | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rSetSpd | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| rFactor | LREAL | VAR_IN | 0.0 | valore atteso dei passi (±0.001) |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bReset | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| rPos | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| rSpeed | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T31 — FUNCTION_BLOCK `SP_GripPlanner` (13_MultiGrip/FB_SP_GripPlanner.st)

**Scopo:** Pianificatore cluster multi-ventosa

**Inventario METHOD (3):** `Begin():ET_SP_RetCode`, `OfferCand():BOOL`, `Finish():ET_SP_RetCode`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_OUTPUT | out_bOk | BOOL | - | Plan valid (Finish called) |
| VAR_OUTPUT | out_bSync | BOOL | - | TRUE = synchronized multi-pick approved |
| VAR_OUTPUT | out_uiN | UINT | - | Final members 1..GC_CUPS |
| VAR_OUTPUT | out_aiIdx | ARRAY[1..4] OF SINT | - | Queue slot per member (1 = anchor) 1..GC_CUPS |
| VAR_OUTPUT | out_aCup | ARRAY[1..4] OF SINT | - | Cup id per member (1 = anchor cup) 1..GC_CUPS |
| VAR_OUTPUT | out_astP | ARRAY[1..4] OF ST_SP_Pose3D | - | Member item poses (capture frame, world) 1..GC_CUPS |
| VAR_OUTPUT | out_stTcp | ST_SP_Pose3D | - | Synchronized TCP pose at the pick event (capture frame) |
| VAR_OUTPUT | out_rW | LREAL | - | Total accepted weight [g] |
| VAR_OUTPUT | out_rCog | LREAL | - | CoG offset from TCP [mm], 0 = unknown |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_GripCfg | - | Configurazione planner |

**Precondizioni:** `Begin()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `OfferCand` con 3 pezzi allineati (pitch 40 mm) e 2 ventose a 80 mm. | `Finish` restituisce cluster di 2 pezzi compatibili. |
| 2 | `OfferCand` con pezzi casuali. | Nessun cluster (residuo oltre soglia). |
| 3 | `OfferCand` con 3 pezzi allineati e 4 ventose. | Cluster fino a 4 (cap `GC_CUPS`). |
| 4 | Yaw di cluster: pezzi a 10° e 20°. | `FUN_SP_FitYaw` → 15° ± 0.5. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-GP1 | `Finish` senza `Begin`. | `ErrState`. |
| FT-GP2 | Pezzi con orientamenti opposti (0° e 180°). | Nessun cluster forzato. |

**Criterio FB-T31:** PASS se: clustering geometricamente corretto e ripetibile.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| out_bOk | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_bSync | BOOL | VAR_OUTPUT | FALSE | transizioni attese secondo i passi |
| out_uiN | UINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_aiIdx | ARRAY[1..4] OF SINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_aCup | ARRAY[1..4] OF SINT | VAR_OUTPUT | - | valore atteso dei passi |
| out_astP | ARRAY[1..4] OF ST_SP_Pose3D | VAR_OUTPUT | - | valore atteso dei passi |
| out_stTcp | ST_SP_Pose3D | VAR_OUTPUT | - | valore atteso dei passi |
| out_rW | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |
| out_rCog | LREAL | VAR_OUTPUT | 0.0 | valore atteso dei passi (±0.001) |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T32 — FUNCTION_BLOCK `SP_Collision` (14_Collision/FB_SP_Collision.st)

**Scopo:** Gestione collisioni robot-robot e limiti zona

**Inventario METHOD (3):** `Configure():ET_SP_RetCode`, `ZoneLimOf():LREAL`, `PairSharesZone():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bEnable | BOOL | - | Master gate (FALSE = transparent) |
| VAR_IN | bSysRun | BOOL | - | FALSE = production stopped: release all |
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] (wait-time accounting) |
| VAR_IN | ap2Pos | ARRAY[1..4] OF ST_SP_Pose2D | - | Current TCP positions (world frame) 1..GC_ROBOTS |
| VAR_IN | aiReq | ARRAY[1..4] OF ARRAY[1..2] OF SINT | - |  |
| VAR_IN | stCfg | ST_SP_ColCfg | - | Public configuration (Main/HMI write, mirrors ST_SP_ColCfg) |
| VAR_OUTPUT | astRob | ARRAY[1..4] OF ST_SP_RobCol | - | Per-robot verdict (grant + velocity scale + reason) 1..GC_ROBOTS |
| VAR_OUTPUT | astZd | ARRAY[1..8] OF ST_SP_ZoneDiag | - | Per-zone diagnostics 1..GC_ZONES |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_ColCfg | - | Configurazione |

**Precondizioni:** `Configure()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `ZoneLimOf(1)` con robot in zona mista. | Restituisce il limite (SepSlow/SepStop) corretto. |
| 2 | `PairSharesZone(1,2)` con robot in zone distinte. | FALSE — nessun vincolo. |
| 3 | Due robot simulati a 400 mm (SepSlow=450, SepStop=250). | `bSlowRob` = TRUE su entrambi; `bStopRob` = FALSE. |
| 4 | Avvicinamento a 240 mm. | `bStopRob` = TRUE; movimento fermato. |
| 5 | Allontanamento a 470 mm. | Stop rilasciato; slow persiste finché < 500 mm (isteresi). |
| 6 | Tutti i robot fermi (velocità 0). | Il FB considera solo distanze TCP (verificare). |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-CL1 | Robot con posizione uguale (0 mm). | Stop immediato, nessuna oscillazione. |
| FT-CL2 | Configurazione SepStop > SepSlow. | Scambio automatico o errore `ErrParam` (documentare). |

**Criterio FB-T32:** PASS se: soglie rispettate al mm, isteresi verificata, nessuna oscillazione.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bEnable | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bSysRun | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| ap2Pos | ARRAY[1..4] OF ST_SP_Pose2D | VAR_IN | - | valore atteso dei passi |
| aiReq | ARRAY[1..4] OF ARRAY[1..2] OF SINT | VAR_IN | - | valore atteso dei passi |
| stCfg | ST_SP_ColCfg | VAR_IN | - | valore atteso dei passi |
| astRob | ARRAY[1..4] OF ST_SP_RobCol | VAR_OUTPUT | - | valore atteso dei passi |
| astZd | ARRAY[1..8] OF ST_SP_ZoneDiag | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T33 — FUNCTION_BLOCK `SP_Maint` (15_Professional/FB_SP_Maint.st)

**Scopo:** Manutenzione predittiva (ore lavoro, scadenze)

**Inventario METHOD (1):** `ResetAll():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bPumpOn | BOOL | - | Vacuum pump running |
| VAR_IN | stCfg | ST_SP_MaintCfg | - | Configuration: thresholds (0 = counter disabled). Main/HMI write. |
| VAR_IN | audiRobPicks | ARRAY[1..4] OF UDINT | - | Lifetime picks per robot 1..GC_ROBOTS |
| VAR_IN | audiCamTrig | ARRAY[1..2] OF UDINT | - | Lifetime triggers per camera 1..GC_CAMS |
| VAR_IN | abConvRun | ARRAY[1..8] OF BOOL | - | Conveyor running 1..GC_FEEDS |
| VAR_OUTPUT | stStat | ST_SP_MaintStat | - | Published maintenance state (mirrored to the HMI by Main) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_MaintCfg | - | Configurazione scadenze |

**Precondizioni:** `ResetAll()` eseguito.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Far avanzare 10 h simulate (ore lavoro). | Contatori ore aggiornati. |
| 2 | Impostare soglia scadenza a 5 h. | A 5 h: flag `bDue` = TRUE; allarme manutenzione generato. |
| 3 | `ResetAll()` dopo la manutenzione. | Contatori azzerati; allarme rimosso. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-MT1 | Soglia 0. | Nessun allarme continuo (gestione dedicata). |

**Criterio FB-T33:** PASS se: scadenze e reset corretti.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bPumpOn | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| stCfg | ST_SP_MaintCfg | VAR_IN | - | valore atteso dei passi |
| audiRobPicks | ARRAY[1..4] OF UDINT | VAR_IN | - | valore atteso dei passi |
| audiCamTrig | ARRAY[1..2] OF UDINT | VAR_IN | - | valore atteso dei passi |
| abConvRun | ARRAY[1..8] OF BOOL | VAR_IN | - | valore atteso dei passi |
| stStat | ST_SP_MaintStat | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T34 — FUNCTION_BLOCK `SP_Oee` (15_Professional/FB_SP_Oee.st)

**Scopo:** Calcolo OEE (A, P, Q, OEE, MTBF/MTTR)

**Inventario METHOD (2):** `Reset():BOOL`, `MTReset():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | uiDtMs | UDINT | - | Task period [ms] |
| VAR_IN | bShift | BOOL | - | TRUE = shift running (planned time accrues) |
| VAR_IN | bFault | BOOL | - | TRUE = any robot/system fault active |
| VAR_IN | stCnt | ST_SP_Counters | - | Statistics snapshot (SP_Stats totals, written by Main every cycle) |
| VAR_IN | rIdealCycleMs | LREAL | 2000.0 | Ideal cycle time per piece [ms] (performance reference) |
| VAR_OUTPUT | stView | ST_SP_OeeView | - | OEE snapshot (mirrored to the HMI by Main) |

**Precondizioni:** `Reset()` e `MTReset()` eseguiti.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Tempo pianificato 60 min, tempo di fermo 6 min. | `rA = 0.90` ± 0.001. |
| 2 | Conteggio ideale 100 pezzi, reali 90. | `rP = 0.90` ± 0.001. |
| 3 | Good 85, totali 90. | `rQ = 0.9444` ± 0.001. |
| 4 | Verifica combinata. | `rOee = A·P·Q = 0.765` ± 0.001. |
| 5 | `MTReset` con 2 guasti in 10 h. | MTBF = 5 h; MTTR = tempo medio di ripristino impostato. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-OEE1 | Divisione per zero (tempo 0). | Ritorno 0.0, nessun crash. |

**Criterio FB-T34:** PASS se: formule OEE verificate al millesimo.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| uiDtMs | UDINT | VAR_IN | 0 | incrementa coerentemente agli stimoli |
| bShift | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| bFault | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| stCnt | ST_SP_Counters | VAR_IN | - | valore atteso dei passi |
| rIdealCycleMs | LREAL | VAR_IN | 2000.0 | valore atteso dei passi (±0.001) |
| stView | ST_SP_OeeView | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

### FB-T35 — FUNCTION_BLOCK `SP_SelfTest` (15_Professional/FB_SP_SelfTest.st)

**Scopo:** Self-test di accensione (RAM, parametri, I/O)

**Inventario METHOD (1):** `Close():BOOL`

**Interfaccia (VAR_IN / VAR_OUT / VAR_IN_OUT):**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_IN | bRun | BOOL | - | One-shot trigger (HMI command or recipe-load hook) |
| VAR_IN | stNow | Yt_YA_RTC_Struct | - | Wall clock stamp (from TaskSvc) |
| VAR_OUTPUT | stRes | ST_SP_TestRes | - | Result record (mirrored to the HMI by Main) |

**Setup del test:**

| Parametro | Tipo | Valore | Note |
|---|---|---|---|
| stCfg | ST_SP_SelfCfg | - | Configurazione |

**Precondizioni:** Esecuzione all'avvio.

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Avvio con configurazione valida. | Tutti i test interni → `Done`; nessun allarme. |
| 2 | Forzare un parametro fuori range. | Il test corrispondente → `ErrParam` con descrizione. |
| 3 | `Close()` al termine. | Risorse rilasciate; stato aggiornato. |

**Sotto-test di robustezza:**

| ID | Stimolo di guasto | Comportamento atteso |
|---|---|---|
| FT-SS1 | Due parametri corrotti. | Entrambi segnalati con ID distinti. |

**Criterio FB-T35:** PASS se: tutti i sotto-test passano con configurazione valida.

**Tabella di collaudo Watch — variabili da osservare (stato a riposo → durante il test):**

| Variabile | Tipo | Kind | A riposo | Durante il test |
|---|---|---|---|---|
| bRun | BOOL | VAR_IN | FALSE | transizioni attese secondo i passi |
| stNow | Yt_YA_RTC_Struct | VAR_IN | - | valore atteso dei passi |
| stRes | ST_SP_TestRes | VAR_OUTPUT | - | valore atteso dei passi |

**Casi limite aggiuntivi (obbligatori per il certificato del modulo):**

| Caso | Stimolo | Comportamento atteso |
|---|---|---|
| CL-1 | Doppia chiamata dello stesso comando nello stesso ciclo del task. | Effetto idempotente o cumulativo documentato; nessuna corruzione di stato. |
| CL-2 | Parametri al limite: 0, valori massimi del tipo, stringhe vuote. | Nessun crash; ritorni deterministici (`ErrParam` dove previsto). |
| CL-3 | Sequenza pseudocasuale di 100 chiamate miste (tutti i METHOD). | Stato finale coerente; contatori pari alla somma degli effetti attesi. |
| CL-4 | Chiamata del metodo di reset con dati presenti. | Ritorno allo stato di riposo della tabella Watch qui sopra. |
| CL-5 | Chiamata con il FB disabilitato (bEnable=FALSE o stato di fermo). | Nessun effetto sugli output; ripresa pulita alla riattivazione. |
| CL-6 | Chiamata contemporanea dai task Main (10 ms) e Svc (100 ms). | Nessuna corruzione dati (verificare `udiStatDrop=0` e contatori coerenti). |


---

## Sezione 4 — Matrice di copertura dei 209 METHOD (M-*)

Per ogni METHOD si fornisce: firma, parametri e **verifica attesa**. Il test si esegue nell'ambito del test del FB corrispondente (Sezione 3), chiamando il metodo con gli argomenti della riga e verificando l'effetto indicato.

#### M — `SP_AlarmMgr.ActiveCount(): UINT` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `ActiveCount((nessun parametro))`

**Verifica attesa:** Restituisce il numero di allarmi attivi (0 se nessuno).

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.Raise(): BOOL` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `Raise(uiId : UINT, eSrc : ET_SP_LogSource, eLevel : ET_SP_LogLevel, sText : STRING(80))`

**Verifica attesa:** La voce viene inserita nel registro con code/severity/sorgente/messaggio; `ActiveCount` incrementa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.Clear(): BOOL` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `Clear(uiId : UINT)`

**Verifica attesa:** La voce indicata viene disattivata; `ActiveCount` decrementa.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.Ack(): BOOL` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `Ack(uiId : UINT)`

**Verifica attesa:** La voce indicata passa `bAck=TRUE`; `uiUnack` decrementa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.AckAll(): UINT` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `AckAll((nessun parametro))`

**Verifica attesa:** Tutte le voci attive passano `bAck=TRUE`; `uiUnack=0`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.GetEntry(): BOOL` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `GetEntry(iIdx : UINT)`

**Verifica attesa:** Restituisce la copia della voce richiesta; indice invalido → voce vuota.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_AlarmMgr.GetActive(): BOOL` (01_Common/FB_SP_AlarmMgr.st)

**Chiamata tipo:** `GetActive(iFromId : UINT)`

**Verifica attesa:** Restituisce l'elenco delle voci attive in ordine di inserimento.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.Log(): UDINT` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `Log(eLevel : ET_SP_LogLevel, eSrc : ET_SP_LogSource, uiCode : UINT, sText : STRING(120))`

**Verifica attesa:** Inserisce la voce di log; `uiCount` incrementa (satura a GC_LOG_N).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.LogInfo(): UDINT` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `LogInfo(eSrc : ET_SP_LogSource, sText : STRING(120))`

**Verifica attesa:** Come `Log` con livello INFO.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.LogWarn(): UDINT` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `LogWarn(eSrc : ET_SP_LogSource, sText : STRING(120))`

**Verifica attesa:** Come `Log` con livello WARN.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.LogError(): UDINT` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `LogError(eSrc : ET_SP_LogSource, uiCode : UINT, sText : STRING(120))`

**Verifica attesa:** Come `Log` con livello ERROR.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.GetEntry(): BOOL` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `GetEntry(iIdx : UINT)`

**Verifica attesa:** Restituisce la copia della voce richiesta; indice invalido → voce vuota.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.ExportLine(): BOOL` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `ExportLine(iIdx : UINT)`

**Verifica attesa:** Restituisce la riga CSV della voce richiesta.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Logger.Clear(): UINT` (01_Common/FB_SP_Logger.st)

**Chiamata tipo:** `Clear((nessun parametro))`

**Verifica attesa:** La voce indicata viene disattivata; `ActiveCount` decrementa.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Calib2D.Reset(): BOOL` (02_Geometry/FB_SP_Calib2D.st)

**Chiamata tipo:** `Reset((nessun parametro))`

**Verifica attesa:** Azzera le statistiche.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Calib2D.AddPair(): ET_SP_RetCode` (02_Geometry/FB_SP_Calib2D.st)

**Chiamata tipo:** `AddPair(rCx : LREAL, rCy : LREAL, rWx : LREAL, rWy : LREAL)`

**Verifica attesa:** Registra la coppia pixel/mondo; oltre `GC_CALIB_PTS` la coppia è rifiutata.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Calib2D.Compute(): ET_SP_RetCode` (02_Geometry/FB_SP_Calib2D.st)

**Chiamata tipo:** `Compute((nessun parametro))`

**Verifica attesa:** Stima i parametri della similitudine; errore su dati insufficienti/singolari.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Conveyor.Configure(): ET_SP_RetCode` (03_Conveyor/FB_SP_Conveyor.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_ConvCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Conveyor.FactorFor(): LREAL` (03_Conveyor/FB_SP_Conveyor.st)

**Chiamata tipo:** `FactorFor(rNearDist : LREAL)`

**Verifica attesa:** Restituisce il fattore di velocità per la distanza del pezzo più vicino.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Conveyor.InWindow(): BOOL` (03_Conveyor/FB_SP_Conveyor.st)

**Chiamata tipo:** `InWindow(rBeltOff : LREAL)`

**Verifica attesa:** TRUE se la posizione è nella finestra [rFrom..rTo].

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.BuildTrig(): STRING(64)` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `BuildTrig((nessun parametro))`

**Verifica attesa:** Costruisce la stringa di trigger secondo il protocollo del driver.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.RespComplete(): BOOL` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `RespComplete(udiTickMs : UDINT)`

**Verifica attesa:** TRUE quando il buffer di risposta è completo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.m_ParseLine(): BOOL` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `m_ParseLine((nessun parametro))`

**Verifica attesa:** Parsing di una riga: campi estratti e validati.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.m_ParseFields(): BOOL` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `m_ParseFields(sLine : STRING(64))`

**Verifica attesa:** Estrazione campi multipli da una riga.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.GetItem(): BOOL` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `GetItem((nessun parametro))`

**Verifica attesa:** Restituisce l'i-esimo item dello scatto; oltre il numero → non valido.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.ClearItems(): UDINT` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `ClearItems((nessun parametro))`

**Verifica attesa:** Svuota il buffer item.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvAscii.Configure(): ET_SP_RetCode` (04_Vision/FB_SP_DrvAscii.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_VisionCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvCognex.Configure(): ET_SP_RetCode` (04_Vision/FB_SP_DrvCognex.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_VisionCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvCognex.GetItem(): BOOL` (04_Vision/FB_SP_DrvCognex.st)

**Chiamata tipo:** `GetItem((nessun parametro))`

**Verifica attesa:** Restituisce l'i-esimo item dello scatto; oltre il numero → non valido.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvCognex.ClearItems(): UDINT` (04_Vision/FB_SP_DrvCognex.st)

**Chiamata tipo:** `ClearItems((nessun parametro))`

**Verifica attesa:** Svuota il buffer item.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvGeneric.Configure(): ET_SP_RetCode` (04_Vision/FB_SP_DrvGeneric.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_VisionCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvGeneric.GetItem(): BOOL` (04_Vision/FB_SP_DrvGeneric.st)

**Chiamata tipo:** `GetItem((nessun parametro))`

**Verifica attesa:** Restituisce l'i-esimo item dello scatto; oltre il numero → non valido.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvGeneric.ClearItems(): UDINT` (04_Vision/FB_SP_DrvGeneric.st)

**Chiamata tipo:** `ClearItems((nessun parametro))`

**Verifica attesa:** Svuota il buffer item.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvKeyence.Configure(): ET_SP_RetCode` (04_Vision/FB_SP_DrvKeyence.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_VisionCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvKeyence.GetItem(): BOOL` (04_Vision/FB_SP_DrvKeyence.st)

**Chiamata tipo:** `GetItem((nessun parametro))`

**Verifica attesa:** Restituisce l'i-esimo item dello scatto; oltre il numero → non valido.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_DrvKeyence.ClearItems(): UDINT` (04_Vision/FB_SP_DrvKeyence.st)

**Chiamata tipo:** `ClearItems((nessun parametro))`

**Verifica attesa:** Svuota il buffer item.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Socket.PollRx(): BOOL` (04_Vision/FB_SP_Socket.st)

**Chiamata tipo:** `PollRx((nessun parametro))`

**Verifica attesa:** Aggiorna il buffer di ricezione dal canale.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Socket.TakeRx(): BOOL` (04_Vision/FB_SP_Socket.st)

**Chiamata tipo:** `TakeRx((nessun parametro))`

**Verifica attesa:** Estrae il primo frame FIFO.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Socket.RxCount(): UINT` (04_Vision/FB_SP_Socket.st)

**Chiamata tipo:** `RxCount((nessun parametro))`

**Verifica attesa:** Numero di frame in coda.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Socket.RxOverflow(): BOOL` (04_Vision/FB_SP_Socket.st)

**Chiamata tipo:** `RxOverflow((nessun parametro))`

**Verifica attesa:** TRUE se il buffer ha saturato.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.ResetPolicy(): BOOL` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `ResetPolicy((nessun parametro))`

**Verifica attesa:** Riporta la policy camera allo stato iniziale.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.PolicyEngine(): BOOL` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `PolicyEngine((nessun parametro))`

**Verifica attesa:** Esegue un passo della macchina a stati della policy.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.Fire(): BOOL` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `Fire((nessun parametro))`

**Verifica attesa:** Comanda uno scatto.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.HarvestFromDrv(): SINT` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `HarvestFromDrv(bFromEng : BOOL)`

**Verifica attesa:** Trasferisce gli item dal driver alla camera.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.GetNextItem(): BOOL` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `GetNextItem((nessun parametro))`

**Verifica attesa:** Restituisce il prossimo item simulato.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.InjectItem(): ET_SP_RetCode` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `InjectItem(stVi : ST_SP_VisionItem, iFeed : SINT)`

**Verifica attesa:** Inserisce un item artificiale (test/simulazione).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.TriggerNow(): BOOL` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `TriggerNow((nessun parametro))`

**Verifica attesa:** Scatta immediatamente (bypass del trigger a distanza).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_VisionCam.Configure(): ET_SP_RetCode` (04_Vision/FB_SP_VisionCam.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_VisionCfg, iCam : SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.PublishCounts(): BOOL` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `PublishCounts((nessun parametro))`

**Verifica attesa:** Aggiorna i contatori pubblicati su GVL.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.Configure(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_TrkCfg)`

**Verifica attesa:** Applica `rDupTol`, `rAgeMs`, `rWinBehind` alla coda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.FindDuplicate(): SINT` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `FindDuplicate(stItem : ST_SP_TrkItem)`

**Verifica attesa:** Cerca un doppione proiettando i pezzi esistenti a `rEncCap` del candidato; ritorna l'ID del doppione o 0.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.Add(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `Add(stItem : ST_SP_TrkItem)`

**Verifica attesa:** Inserisce un item con rilevamento doppioni; incrementa `udiFed` solo per pezzi nuovi.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.ItemOffset(): LREAL` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `ItemOffset(stIt : ST_SP_TrkItem, rEncNow : LREAL)`

**Verifica attesa:** Restituisce l'offset longitudinale del pezzo rispetto alla posizione di riferimento.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.Reserve(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `Reserve(stReq : ST_SP_ResReq, rEncNow : LREAL, rBeltSpd : LREAL)`

**Verifica attesa:** Riserva il pezzo per un robot; stato → `Reserved`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.ReserveCluster(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `ReserveCluster(stCl : ST_SP_ClReq, rEncNow : LREAL, rBeltSpd : LREAL)`

**Verifica attesa:** Riserva N pezzi sincronizzandone `rEncCap` (cross-shot encoder sync).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.Release(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `Release(iIdx : SINT)`

**Verifica attesa:** Rilascia una riserva; stato → `Tracked`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.CompletePick(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `CompletePick(iIdx : SINT, bOk : BOOL, uiMaxTry : UINT)`

**Verifica attesa:** Conferma la prenda; stato → `Picked`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.GetItem(): BOOL` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `GetItem(iIdx : SINT)`

**Verifica attesa:** Restituisce l'i-esimo item dello scatto; oltre il numero → non valido.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.SetPlaced(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `SetPlaced(iIdx : SINT)`

**Verifica attesa:** Conferma la posa; stato → `Placed`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.NearDist(): BOOL` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `NearDist(rEncNow : LREAL)`

**Verifica attesa:** Distanza del pezzo più vicino dalla posizione data.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.Housekeeping(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `Housekeeping(rEncNow : LREAL)`

**Verifica attesa:** Rimuove pezzi scaduti e aggiorna le età.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.AgeItems(): BOOL` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `AgeItems(uiDtMs : UDINT)`

**Verifica attesa:** Invecchia i pezzi di un ciclo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.ClearAll(): UINT` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `ClearAll((nessun parametro))`

**Verifica attesa:** Svuota la coda item e azzera `uiTracked/udiFed/udiDup/udiRes`.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ItemQueue.AddRaw(): ET_SP_RetCode` (05_Tracking/FB_SP_ItemQueue.st)

**Chiamata tipo:** `AddRaw(stItem : ST_SP_TrkItem)`

**Verifica attesa:** Inserimento raw senza filtro doppioni (diagnostica).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.Configure(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_TrkCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.FeedItem(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `FeedItem(stVi : ST_SP_VisionItem, iCam : SINT)`

**Verifica attesa:** Delega l'inserimento pezzo a `SP_ItemQueue.Add`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.AddTarget(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `AddTarget(stTarget : ST_SP_TrkItem)`

**Verifica attesa:** Aggiunge un target di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.Reserve(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `Reserve(stReq : ST_SP_ResReq, rEncNow : LREAL, rBeltSpd : LREAL)`

**Verifica attesa:** Riserva il pezzo per un robot; stato → `Reserved`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.ReserveCluster(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `ReserveCluster(stCl : ST_SP_ClReq, rEncNow : LREAL, rBeltSpd : LREAL)`

**Verifica attesa:** Riserva N pezzi sincronizzandone `rEncCap` (cross-shot encoder sync).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.CompletePick(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `CompletePick(iIdx : SINT, bOk : BOOL, uiMaxTry : UINT)`

**Verifica attesa:** Conferma la prenda; stato → `Picked`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.Release(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `Release(iIdx : SINT)`

**Verifica attesa:** Rilascia una riserva; stato → `Tracked`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.PlaceTarget(): ET_SP_RetCode` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `PlaceTarget(iIdx : SINT)`

**Verifica attesa:** Aggiorna il target dopo la posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.NearDist(): BOOL` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `NearDist(rEncNow : LREAL)`

**Verifica attesa:** Distanza del pezzo più vicino dalla posizione data.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.Housekeeping(): BOOL` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `Housekeeping(rEncNow : LREAL, uiDtMs : UDINT)`

**Verifica attesa:** Rimuove pezzi scaduti e aggiorna le età.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_TrkFeed.ResetAll(): BOOL` (05_Tracking/FB_SP_TrkFeed.st)

**Chiamata tipo:** `ResetAll((nessun parametro))`

**Verifica attesa:** Svuota le code delegate e azzera i contatori.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.CountActive(): UINT` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `CountActive((nessun parametro))`

**Verifica attesa:** Numero di batch attivi.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.AddBatch(): SINT` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `AddBatch(stDef : ST_SP_BatchDef)`

**Verifica attesa:** Aggiunge un batch; oltre `GC_BATCHES` → errore.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.SetBatch(): ET_SP_RetCode` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `SetBatch(iIdx : SINT, stDef : ST_SP_BatchDef)`

**Verifica attesa:** Imposta il batch attivo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.StartBatch(): ET_SP_RetCode` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `StartBatch(iIdx : SINT)`

**Verifica attesa:** Avvia la generazione del pattern.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.StopBatch(): ET_SP_RetCode` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `StopBatch(iIdx : SINT)`

**Verifica attesa:** Ferma il batch mantenendo il progresso.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.GetActive(): SINT` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `GetActive(iFeed : SINT)`

**Verifica attesa:** Restituisce l'elenco delle voci attive in ordine di inserimento.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.GetDef(): BOOL` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `GetDef(iIdx : SINT)`

**Verifica attesa:** Restituisce la definizione del batch.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.GetStat(): BOOL` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `GetStat(iIdx : SINT)`

**Verifica attesa:** Restituisce le statistiche del batch.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.GetId(): UDINT` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `GetId(iIdx : SINT)`

**Verifica attesa:** Restituisce l'ID del batch richiesto.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.SyncProgress(): BOOL` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `SyncProgress(iIdx : SINT, stStat : ST_SP_BatchStat)`

**Verifica attesa:** Aggiorna il progresso; al termine `bComplete=TRUE`.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_BatchMgr.ClearAll(): UINT` (06_Pattern/FB_SP_BatchMgr.st)

**Chiamata tipo:** `ClearAll((nessun parametro))`

**Verifica attesa:** Azzera tutti i batch (registro e contatori).

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.Configure(): ET_SP_RetCode` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `Configure(stWorld : ST_SP_Transf2D, rZBelt : LREAL, iDir : SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.StartBatch(): ET_SP_RetCode` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `StartBatch(stDef : ST_SP_BatchDef, stPatt : ST_SP_PattDef, udiBatchId : UDINT)`

**Verifica attesa:** Avvia la generazione del pattern.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.AbortBatch(): BOOL` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `AbortBatch((nessun parametro))`

**Verifica attesa:** Interrompe la generazione.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.OnSensor(): BOOL` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `OnSensor(rEncNow : LREAL)`

**Verifica attesa:** Gestisce il fronte sensore (anti-rimbalzo).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.Engine(): BOOL` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `Engine(rEncNow : LREAL)`

**Verifica attesa:** Esegue un passo del generatore di pattern.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.NewTray(): BOOL` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `NewTray((nessun parametro))`

**Verifica attesa:** Genera un nuovo piano di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.MixType(): UINT` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `MixType((nessun parametro))`

**Verifica attesa:** Assegna la sequenza dei tipi nel batch.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.PushTarget(): ET_SP_RetCode` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `PushTarget(stT : ST_SP_TrkItem)`

**Verifica attesa:** Inserisce un target nella coda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.GetNextTarget(): BOOL` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `GetNextTarget((nessun parametro))`

**Verifica attesa:** Estrae il target corrente.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_PatternGen.NotifyPlaced(): ET_SP_RetCode` (06_Pattern/FB_SP_PatternGen.st)

**Chiamata tipo:** `NotifyPlaced(uiSlot : UINT)`

**Verifica attesa:** Conferma la posa del target corrente.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.Configure(): ET_SP_RetCode` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_ShareCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.Eligible(): BOOL` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `Eligible(stRob : ST_SP_RobShare, stOffer : ST_SP_Offer, bCheckType : BOOL)`

**Verifica attesa:** TRUE se il robot è utilizzabile per l'assegnazione.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.OfferProduct(): SINT` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `OfferProduct(stOffer : ST_SP_Offer, astRob : ARRAY[1..4] OF ST_SP_RobShare)`

**Verifica attesa:** Offre un pezzo al miglior robot secondo la strategia.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.m_Organic(): SINT` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `m_Organic(stOffer : ST_SP_Offer, astRob : ARRAY[1..4] OF ST_SP_RobShare, bTryAny : BOOL)`

**Verifica attesa:** Strategia organica: assegnamento per prossimità dinamica.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.m_Greedy(): SINT` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `m_Greedy(stOffer : ST_SP_Offer, astRob : ARRAY[1..4] OF ST_SP_RobShare, bTryAny : BOOL)`

**Verifica attesa:** Strategia greedy: sempre al robot più vicino.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.m_Balanced(): SINT` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `m_Balanced(stOffer : ST_SP_Offer, astRob : ARRAY[1..4] OF ST_SP_RobShare, bTryAny : BOOL)`

**Verifica attesa:** Strategia bilanciata: pareggia i conteggi di pick.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_LoadBalancer.m_Manual(): SINT` (07_LoadSharing/FB_SP_LoadBalancer.st)

**Chiamata tipo:** `m_Manual(stOffer : ST_SP_Offer, astRob : ARRAY[1..4] OF ST_SP_RobShare, bTryAny : BOOL)`

**Verifica attesa:** Strategia manuale: segue la mappa impostata.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ZoneGuard.Configure(): ET_SP_RetCode` (07_LoadSharing/FB_SP_ZoneGuard.st)

**Chiamata tipo:** `Configure(aiFeedZone : ARRAY[1..8] OF SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RobMotion.SimBody(): BOOL` (08_Robot/FB_SP_RobMotion.st)

**Chiamata tipo:** `SimBody((nessun parametro))`

**Verifica attesa:** Aggiorna la posa del corpo simulato per un ciclo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.Configure(): ET_SP_RetCode` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_RobCfg, iRobot : SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.OfferJob(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `OfferJob(stJob : ST_SP_Job)`

**Verifica attesa:** Offre un job al robot; stato FSM → Pick.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CancelJob(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CancelJob((nessun parametro))`

**Verifica attesa:** Annulla il job corrente e rilascia gli item.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.MarkFault(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `MarkFault((nessun parametro))`

**Verifica attesa:** Porta il robot in fault.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.ClearFault(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `ClearFault((nessun parametro))`

**Verifica attesa:** Rimuove il fault.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.EnterFault(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `EnterFault(uiId : UINT)`

**Verifica attesa:** Fault esterno con motivo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.SetBeltFrames(): ET_SP_RetCode` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `SetBeltFrames(astTrk : ARRAY[1..8] OF ST_SP_TrkCfg)`

**Verifica attesa:** Imposta i frame dei nastri per il tracking.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CompBeltTargets(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CompBeltTargets(stBase : ST_SP_Pose3D, iFeed : SINT, stItem : ST_SP_TrkItem, bPlaceSel : BOOL)`

**Verifica attesa:** Compensa i target in funzione dei frame nastro.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.MvToBelt(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `MvToBelt(stT : ST_SP_Pose3D, stB : ST_SP_Pose3D, rVel : LREAL, ePrec : ET_SP_Precision)`

**Verifica attesa:** Muove a target su nastro (tracking).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.LatchCmds(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `LatchCmds((nessun parametro))`

**Verifica attesa:** Aggancia i comandi di presa/posa al ciclo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.MvTo(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `MvTo(stT : ST_SP_Pose3D, eKind : ET_SP_MvKind, rVel : LREAL, ePrec : ET_SP_Precision)`

**Verifica attesa:** Muove a target fisso.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CupPose(): ST_SP_Pose3D` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CupPose(p3 : ST_SP_Pose3D, uiTool : UINT, uiCup : UINT)`

**Verifica attesa:** Posa assoluta del cup richiesto.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.LoadOff(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `LoadOff(iFeed : SINT, uiType : UINT)`

**Verifica attesa:** Scarica il riferimento di carico dopo la posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CompPickTargets(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CompPickTargets((nessun parametro))`

**Verifica attesa:** Compila i target di prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CompPlaceTargets(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CompPlaceTargets((nessun parametro))`

**Verifica attesa:** Compila i target di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.AdvancePickItem(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `AdvancePickItem((nessun parametro))`

**Verifica attesa:** Avanza l'item di prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.AdvancePlaceItem(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `AdvancePlaceItem((nessun parametro))`

**Verifica attesa:** Avanza l'item di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CloseJob(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CloseJob((nessun parametro))`

**Verifica attesa:** Chiude il job e aggiorna i KPI.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CompSyncPickTargets(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CompSyncPickTargets((nessun parametro))`

**Verifica attesa:** Compila i target di prenda sincronizzati (cluster).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CompSyncPlaceTargets(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CompSyncPlaceTargets((nessun parametro))`

**Verifica attesa:** Compila i target di posa sincronizzati.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.SyncPickPending(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `SyncPickPending((nessun parametro))`

**Verifica attesa:** TRUE se ci sono prese sincronizzate in sospeso.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.SyncPlaceTry(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `SyncPlaceTry((nessun parametro))`

**Verifica attesa:** Tenta la posa sincronizzata.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.CupHolding(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `CupHolding(iCup : SINT)`

**Verifica attesa:** TRUE se la ventosa indicata tiene un pezzo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.Fsm(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `Fsm((nessun parametro))`

**Verifica attesa:** Esegue un passo della macchina a stati del robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.FirstFailedPlace(): SINT` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `FirstFailedPlace((nessun parametro))`

**Verifica attesa:** Identifica la prima ventosa senza pezzo (GripEval).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Robot.Publish(): BOOL` (08_Robot/FB_SP_Robot.st)

**Chiamata tipo:** `Publish((nessun parametro))`

**Verifica attesa:** Aggiorna `GVL_SP_Inst.astRob[i]` per le Watch Table.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.Configure(): ET_SP_RetCode` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `Configure(astTools : ARRAY[1..4] OF ST_SP_ToolCfg, iRobot : SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.AutoCh(): UINT` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `AutoCh(iTool : SINT)`

**Verifica attesa:** Selezione automatica del canale.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.ChPick(): UINT` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `ChPick(iTool : SINT)`

**Verifica attesa:** Imposta il canale di prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.ChPlace(): UINT` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `ChPlace(iTool : SINT)`

**Verifica attesa:** Imposta il canale di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.ChFbk(): UINT` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `ChFbk(iTool : SINT)`

**Verifica attesa:** Imposta il canale di feedback.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.WritePick(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `WritePick(iTool : SINT, bOn : BOOL)`

**Verifica attesa:** Scrive le uscite di prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.WritePlace(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `WritePlace(iTool : SINT, bOn : BOOL)`

**Verifica attesa:** Scrive le uscite di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.FbkOk(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `FbkOk(iTool : SINT)`

**Verifica attesa:** TRUE se il feedback del canale è valido.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.GripStart(): ET_SP_RetCode` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `GripStart(iTool : SINT)`

**Verifica attesa:** Avvia la presa su tutte le ventose.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.GripSync(): ET_SP_RetCode` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `GripSync(iTool : SINT, uiCups : UINT)`

**Verifica attesa:** Sincronizza l'attivazione delle ventose.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.PlaceStart(): ET_SP_RetCode` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `PlaceStart(iTool : SINT)`

**Verifica attesa:** Avvia la posa (con blow-off).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.AbortAll(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `AbortAll((nessun parametro))`

**Verifica attesa:** Spegne tutte le valvole.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.RefreshFbk(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `RefreshFbk((nessun parametro))`

**Verifica attesa:** Aggiorna tutti i feedback.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.FbkCup(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `FbkCup(iTool : SINT, iCup : SINT)`

**Verifica attesa:** Feedback della singola ventosa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.CaptureCups(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `CaptureCups((nessun parametro))`

**Verifica attesa:** Cattura lo stato delle ventose dopo la prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.HoldingOf(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `HoldingOf(iTool : SINT)`

**Verifica attesa:** Restituisce lo stato di carico delle ventose.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_ToolCtl.ResetCounters(): BOOL` (08_Robot/FB_SP_ToolCtl.st)

**Chiamata tipo:** `ResetCounters((nessun parametro))`

**Verifica attesa:** Azzera i contatori dell'attrezzo.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.Configure(): ET_SP_RetCode` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `Configure(stIn : ST_SP_ShareCfg)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.Run(): BOOL` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `Run((nessun parametro))`

**Verifica attesa:** Esegue un passo del dispatcher.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.StepRobot(): BOOL` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `StepRobot(iR : SINT)`

**Verifica attesa:** Avanza di uno stato il job del robot indicato.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.StoreItem(): BOOL` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `StoreItem(iR : SINT, uiCnt : UINT, stRsp : ST_SP_ResRsp, bPick : BOOL, iCup : SINT)`

**Verifica attesa:** Registra l'associazione job-item.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.Abandon(): BOOL` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `Abandon(iR : SINT)`

**Verifica attesa:** Annulla un job attivo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Dispatch.ResetAll(): BOOL` (09_Production/FB_SP_Dispatch.st)

**Chiamata tipo:** `ResetAll((nessun parametro))`

**Verifica attesa:** Azzera lo stato del dispatcher.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.AddPick(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `AddPick(bOk : BOOL, iFeed : SINT)`

**Verifica attesa:** Registra una prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.AddPlace(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `AddPlace(bOk : BOOL, iFeed : SINT)`

**Verifica attesa:** Registra una posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.AddCycle(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `AddCycle((nessun parametro))`

**Verifica attesa:** Registra un tempo di ciclo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.AddAlarm(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `AddAlarm((nessun parametro))`

**Verifica attesa:** Registra un allarme.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.GetFeed(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `GetFeed(iFeed : SINT)`

**Verifica attesa:** Restituisce i dati di alimentazione.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Stats.Reset(): BOOL` (09_Production/FB_SP_Stats.st)

**Chiamata tipo:** `Reset((nessun parametro))`

**Verifica attesa:** Azzera le statistiche.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.Step(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `Step((nessun parametro))`

**Verifica attesa:** Esegue un passo dell'orchestrazione.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.StageOutputs(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `StageOutputs(uiStage : SINT)`

**Verifica attesa:** Aggiorna gli output di sistema.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.BatchService(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `BatchService((nessun parametro))`

**Verifica attesa:** Servizio ciclico dei batch.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.SetBatch(): ET_SP_RetCode` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `SetBatch(iIdx : SINT, stDef : ST_SP_BatchDef)`

**Verifica attesa:** Imposta il batch attivo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.GetBatchDef(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `GetBatchDef(iIdx : SINT)`

**Verifica attesa:** Restituisce la definizione del batch.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.GetBatchStat(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `GetBatchStat(iIdx : SINT)`

**Verifica attesa:** Restituisce le statistiche del batch.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.GetActiveBatch(): SINT` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `GetActiveBatch(iOutFeed : SINT)`

**Verifica attesa:** Restituisce il batch attivo.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.SyncBatchProgress(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `SyncBatchProgress(iIdx : SINT, stPatt : ST_SP_BatchStat)`

**Verifica attesa:** Sincronizza il progresso del batch.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.AddPickStat(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `AddPickStat(bOk : BOOL, iFeed : SINT)`

**Verifica attesa:** Aggiorna le statistiche di prenda.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.AddPlaceStat(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `AddPlaceStat(bOk : BOOL, iFeed : SINT)`

**Verifica attesa:** Aggiorna le statistiche di posa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.AddCycleStat(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `AddCycleStat((nessun parametro))`

**Verifica attesa:** Aggiorna le statistiche di ciclo.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.OnRobotLoss(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `OnRobotLoss((nessun parametro))`

**Verifica attesa:** Gestisce la perdita di un robot (resilienza).

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_System.Publish(): BOOL` (09_Production/FB_SP_System.st)

**Chiamata tipo:** `Publish((nessun parametro))`

**Verifica attesa:** Aggiorna `GVL_SP_Prod.stSys` per le Watch Table.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_FileIo.OpenWrite(): BOOL` (10_Persistence/FB_SP_FileIo.st)

**Chiamata tipo:** `OpenWrite(sPath : STRING(64))`

**Verifica attesa:** Apre un file in scrittura.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_FileIo.OpenRead(): BOOL` (10_Persistence/FB_SP_FileIo.st)

**Chiamata tipo:** `OpenRead(sPath : STRING(64))`

**Verifica attesa:** Apre un file in lettura.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_FileIo.WriteLine(): BOOL` (10_Persistence/FB_SP_FileIo.st)

**Chiamata tipo:** `WriteLine(sLine : STRING(200))`

**Verifica attesa:** Scrive una riga.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_FileIo.CloseNow(): BOOL` (10_Persistence/FB_SP_FileIo.st)

**Chiamata tipo:** `CloseNow((nessun parametro))`

**Verifica attesa:** Chiude il file corrente.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_FileIo.ReadStep(): BOOL` (10_Persistence/FB_SP_FileIo.st)

**Chiamata tipo:** `ReadStep((nessun parametro))`

**Verifica attesa:** Legge la riga successiva.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExportBegin(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExportBegin(sInName : STRING(32))`

**Verifica attesa:** Apre il file di export e scrive l'intestazione.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExportNext(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExportNext((nessun parametro))`

**Verifica attesa:** Esporta la riga successiva.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpConv(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpConv(i : SINT)`

**Verifica attesa:** Esporta la sezione nastro.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpFeed(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpFeed(i : SINT)`

**Verifica attesa:** Esporta la sezione feed.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpCam(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpCam(i : SINT)`

**Verifica attesa:** Esporta la sezione camera.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpCamMap(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpCamMap(i : SINT, k : SINT)`

**Verifica attesa:** Esporta la mappatura camera.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpPatt(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpPatt(i : SINT)`

**Verifica attesa:** Esporta la sezione pattern.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpBatch(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpBatch(i : SINT)`

**Verifica attesa:** Esporta la sezione batch.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpBatchMix(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpBatchMix(i : SINT, k : SINT)`

**Verifica attesa:** Esporta il mix dei batch.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpShare(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpShare(i : SINT)`

**Verifica attesa:** Esporta la sezione load sharing.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ExpShareR(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ExpShareR(i : SINT, k : SINT)`

**Verifica attesa:** Esporta le regole di load sharing.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.ImportLine(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `ImportLine(sLine : STRING(200))`

**Verifica attesa:** Importa una riga di configurazione; errore con numero riga.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RecipeMgr.GetError(): BOOL` (10_Persistence/FB_SP_RecipeMgr.st)

**Chiamata tipo:** `GetError((nessun parametro))`

**Verifica attesa:** Restituisce l'ultimo errore di import.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RetainMgr.Validate(): BOOL` (10_Persistence/FB_SP_RetainMgr.st)

**Chiamata tipo:** `Validate((nessun parametro))`

**Verifica attesa:** TRUE se la configurazione è coerente.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RetainMgr.RestoreDefaults(): BOOL` (10_Persistence/FB_SP_RetainMgr.st)

**Chiamata tipo:** `RestoreDefaults((nessun parametro))`

**Verifica attesa:** Ripristina i valori di fabbrica.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RetainMgr.ChkSum(): UDINT` (10_Persistence/FB_SP_RetainMgr.st)

**Chiamata tipo:** `ChkSum((nessun parametro))`

**Verifica attesa:** Checksum della configurazione.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RetainMgr.SaveNow(): BOOL` (10_Persistence/FB_SP_RetainMgr.st)

**Chiamata tipo:** `SaveNow((nessun parametro))`

**Verifica attesa:** Salva la configurazione in persistenza.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_RetainMgr.SetRecipe(): BOOL` (10_Persistence/FB_SP_RetainMgr.st)

**Chiamata tipo:** `SetRecipe(sName : STRING(32))`

**Verifica attesa:** Applica una ricetta completa.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_SimCamera.SpawnBatch(): UINT` (11_Simulation/FB_SP_SimCamera.st)

**Chiamata tipo:** `SpawnBatch((nessun parametro))`

**Verifica attesa:** Genera un batch di pezzi simulati.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_SimCamera.GetNextItem(): BOOL` (11_Simulation/FB_SP_SimCamera.st)

**Chiamata tipo:** `GetNextItem((nessun parametro))`

**Verifica attesa:** Restituisce il prossimo item simulato.

**Precondizioni:** Stato qualsiasi: il metodo non deve avere effetti collaterali.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_SimCamera.Rand(): LREAL` (11_Simulation/FB_SP_SimCamera.st)

**Chiamata tipo:** `Rand((nessun parametro))`

**Verifica attesa:** Numero pseudo-casuale controllato.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_GripPlanner.Begin(): ET_SP_RetCode` (13_MultiGrip/FB_SP_GripPlanner.st)

**Chiamata tipo:** `Begin(stReq : ST_SP_ClReq, p2Anchor : ST_SP_Pose2D, uiTypeA : UINT, rZAnchor : LREAL, rWAnchor : LREAL)`

**Verifica attesa:** Apre una sessione di clustering.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_GripPlanner.OfferCand(): BOOL` (13_MultiGrip/FB_SP_GripPlanner.st)

**Chiamata tipo:** `OfferCand(iIdx : SINT, stIt : ST_SP_TrkItem)`

**Verifica attesa:** Offre un candidato al cluster corrente.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_GripPlanner.Finish(): ET_SP_RetCode` (13_MultiGrip/FB_SP_GripPlanner.st)

**Chiamata tipo:** `Finish((nessun parametro))`

**Verifica attesa:** Chiude e restituisce il cluster migliore.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Collision.Configure(): ET_SP_RetCode` (14_Collision/FB_SP_Collision.st)

**Chiamata tipo:** `Configure(aiFeedZone : ARRAY[1..8] OF SINT)`

**Verifica attesa:** Applica la configurazione al robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Collision.ZoneLimOf(): LREAL` (14_Collision/FB_SP_Collision.st)

**Chiamata tipo:** `ZoneLimOf(iZone : SINT)`

**Verifica attesa:** Limite di separazione per la zona del robot.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Collision.PairSharesZone(): BOOL` (14_Collision/FB_SP_Collision.st)

**Chiamata tipo:** `PairSharesZone(i : SINT, j : SINT)`

**Verifica attesa:** TRUE se i due robot condividono almeno una zona.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Maint.ResetAll(): BOOL` (15_Professional/FB_SP_Maint.st)

**Chiamata tipo:** `ResetAll((nessun parametro))`

**Verifica attesa:** Azzera i contatori di manutenzione.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Oee.Reset(): BOOL` (15_Professional/FB_SP_Oee.st)

**Chiamata tipo:** `Reset(stCnt : ST_SP_Counters)`

**Verifica attesa:** Azzera le statistiche.

**Precondizioni:** Stato con dati presenti: il metodo deve portare allo stato vuoto/zero.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_Oee.MTReset(): BOOL` (15_Professional/FB_SP_Oee.st)

**Chiamata tipo:** `MTReset((nessun parametro))`

**Verifica attesa:** Azzera le statistiche MTBF/MTTR.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

#### M — `SP_SelfTest.Close(): BOOL` (15_Professional/FB_SP_SelfTest.st)

**Chiamata tipo:** `Close(sMsg : STRING(80))`

**Verifica attesa:** Chiude il self-test.

**Precondizioni:** FB configurato (`Configure` eseguito) e in stato coerente con il metodo; osservare tramite Watch Table.

**Caso limite:** chiamare il metodo due volte consecutive con gli stessi argomenti (idempotenza attesa dove previsto, altrimenti effetto cumulativo documentato) e una volta con argomenti al limite (0 / massimo / vuoto).

**Effetti collaterali attesi:** verificare che i contatori pubblicati (`PublishCounts`/`Publish`) e le code collegate restino coerenti dopo la chiamata; nessun campo `VAR_IN_OUT` del chiamante lasciato non assegnato.

## Sezione 5 — Test dei PROGRAM e dello scheduling (PRG-T01 .. PRG-T04)

I PROGRAM sono il punto di contatto con il runtime: qui si verifica che la ripartizione dei carichi sui 3 task ciclici sia corretta, che non vi siano perdite di dati fra task e che l'inizializzazione sia deterministica.

---

### PRG-T01 — `PRG_SP_ConfigInit` (inizializzazione)

**Firma e variabili:**

| Kind | Nome | Tipo | Default | Descrizione |
|---|---|---|---|---|
| VAR_INPUT | iCfg | SINT | - | Configuration selector 1..8 (see map) |
| VAR_INPUT | bApply | BOOL | - | Rising edge: apply configuration iCfg |
| VAR_INPUT | bAutoBoot | BOOL | TRUE | TRUE: apply iBootCfg on the first cycle |
| VAR_INPUT | iBootCfg | SINT | 1 | Configuration id applied at boot |
| VAR_OUTPUT | bDone | BOOL | - | TRUE for one cycle after a successful apply |
| VAR_OUTPUT | sMsg | STRING(80) | - | Human-readable result of the last apply |
| VAR_OUTPUT | iLastCfg | SINT | - | Last applied configuration id (diagnostic) |
| VAR | m_bOld | BOOL | - | Previous bApply sample (edge detection) |
| VAR | m_bBooted | BOOL | FALSE | Boot auto-apply already done |
| VAR | m_bGo | BOOL | - | Internal apply trigger (edge OR boot) |
| VAR | m_iSel | SINT | - | Resolved configuration id for this apply |
| VAR | m_i | SINT | - | Loop index (feeds / cams / patterns) |
| VAR | m_k | SINT | - | Loop index (robots) |
| VAR | m_stConvClr | ST_SP_ConvCfg | - | Zero template for conveyor configs |
| VAR | m_stFeedClr | ST_SP_TrkCfg | - | Zero template for feed configs |
| VAR | m_stCamClr | ST_SP_VisionCfg | - | Zero template for camera configs |
| VAR | m_stPattClr | ST_SP_PattDef | - | Zero template for pattern defs |
| VAR | m_stBatchClr | ST_SP_BatchDef | - | Zero template for batch defs |
| VAR | m_stShareClr | ST_SP_ShareCfg | - | Zero template for load sharing |
| VAR | m_stSysClr | ST_SP_SysCfg | - | Zero template for system flags |

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Download del programma e cold start. | `PRG_SP_ConfigInit` eseguito una sola volta all'avvio. |
| 2 | Leggere su WT_1: `stSys.eMode`, `stSys.eState`, `stSys.bMotionPermit`. | `eMode = Simulated`, `eState = Idle`, `bMotionPermit = FALSE`. |
| 3 | Verificare che i default siano applicati: `FUN_SP_RobCfgDefault` per ogni robot e `FUN_SP_CamPreset` per ogni camera. | Ogni `astRob[i].stCfg.uiNumTools ≥ 1`; ogni camera `bUsed=TRUE` con driver/porta coerenti. |
| 4 | Verificare i valori di fabbrica dei nastri: `rSlowAhead`, `rStopAhead`, `rSpeedMax`. | Valori coerenti con la configurazione di default documentata. |
| 5 | Warm restart (reset CPU a runtime avviato). | Stato ripristinato coerentemente (nessuna inizializzazione parziale). |
| 6 | Verificare che `GVL_SP_Rtc` sia già popolato al primo ciclo del task Fast. | `udiTickMs` monotono fin dal primo ciclo. |

**Criterio:** inizializzazione deterministica, nessun campo lasciato non inizializzato.

---

### PRG-T02 — `PRG_SP_TaskFast` (task 2 ms)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Attivare il task e misurare il jitter di esecuzione su 1000 cicli. | Tempo ciclo medio 2 ms ± 10%; nessun superamento del watchdog (6 ms). |
| 2 | Verificare che il task gestisca: encoder (`SP_ConvEncoder`), latch trigger, handshake con `GVL_SP_Sync`. | `udiStatDrop = 0` dopo 10 minuti di esecuzione continua. |
| 3 | Forzare un carico artificiale (loop di calcolo) fino a superare i 2 ms. | Il watchdog interviene e viene generato l'allarme dedicato (nessun blocco silenzioso). |
| 4 | Verificare l'ordine di esecuzione interno: lettura input → calcolo → scrittura output. | Nessun output aggiornato prima del calcolo (verifica logica su WT). |
| 5 | Confrontare `udiTickMs` prima/dopo 60 s. | Incremento = 60000 ± 50 ms. |

**Criterio:** nessuna perdita di handshake, jitter nei limiti, watchdog funzionante.

---

### PRG-T03 — `PRG_SP_TaskMain` (task 10 ms)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Attivare il task: esegue `SP_System.Step`, `SP_Dispatch.Run`, `SP_TrkFeed.Housekeeping` (verificare l'ordine effettivo nel sorgente). | Ordine di elaborazione coerente con il design: visione→tracking→dispatch→robot. |
| 2 | Simulare 100 pezzi in 60 s (1.67 pezzi/s). | Tutti tracciati, nessuna perdita: `udiFed = 100`, `uiTracked` coerente. |
| 3 | Misurare il tempo di esecuzione del task con 64 item in coda. | < 30% del ciclo (3 ms) — margine sufficiente. |
| 4 | Verificare la coerenza dei dati letti da `GVL_SP_Sync` (scrittura da Fast). | Nessun dato strappato (tutti gli aggiornamenti atomici o doppi-bufferati). |
| 5 | Forzare `bEStop` durante l'esecuzione. | Entro 1 ciclo del Main: `bMotionPermit = FALSE`, stati robot in stop. |

**Criterio:** nessuna perdita di pezzi, tempi di ciclo nei limiti, reazione E-Stop entro 10 ms.

---

### PRG-T04 — `PRG_SP_TaskSvc` (task 100 ms)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Attivare il task: gestisce log, allarmi, KPI, manutenzione, persistenza ciclica. | `SP_Logger`, `SP_AlarmMgr`, `SP_Oee`, `SP_Maint` aggiornati ogni 100 ms. |
| 2 | Verificare che il salvataggio ciclico di `SP_RetainMgr` non blocchi il task Main. | Nessun aumento del jitter del task Fast/Main durante il salvataggio. |
| 3 | Generare 20 allarmi in 1 secondo. | Tutti registrati e visibili su WT_4; nessuna perdita. |
| 4 | Verificare i KPI su WT_4 dopo 10 minuti di produzione simulata. | `stOee` coerente con i conteggi di `SP_Stats` (riconciliazione entro ±1%). |
| 5 | Misurare il tempo di esecuzione del task con 64 allarmi attivi. | < 30 ms. |

**Criterio:** KPI coerenti, nessun blocco dei task veloci, gestione allarmi completa.

---

### PRG-T05 — Test di carico incrociato (bonus, obbligatorio prima della Sez. 6)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Eseguire contemporaneamente: 4 robot in ciclo, 8 nastri attivi, 2 camere a 5 Hz, export ricetta, 30 allarmi. | Tutti i task nei tempi; `udiStatDrop = 0`. |
| 2 | Durata: 30 minuti. | Nessun watchdog, nessuna perdita di pezzi, contatori coerenti. |
| 3 | Verificare la memoria: nessun leak (conteggi code stabili). | `GC_QUEUE` items max, `GC_LOG_N` e `GC_ALARM_N` saturi ma stabili. |

**Criterio:** sistema stabile sotto carico combinato per 30 minuti.

---

### PRG-T06 — Coerenza dati cross-task (2 ms / 10 ms / 100 ms)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Scrivere da `PRG_SP_TaskFast` un contatore su `GVL_SP_Sync` e leggerlo da `PRG_SP_TaskMain`. | Valore sempre coerente (mai strappato): verificare con sequenze a pattern alternato 0xAAAAAAAA/0x55555555. |
| 2 | Ripetere per lo scambio Main → Svc. | Nessuna incoerenza in 10 minuti. |
| 3 | Misurare `udiStatDrop`. | 0 per tutta la durata. |
| 4 | Forzare un ritardo del task Svc (carico). | Fast e Main non risentono del ritardo. |
| 5 | Verificare lordine di lettura/scrittura dei comandi HMI (debounce). | Nessun comando perso, nessun doppio fronte elaborato. |

**Criterio:** zero dati strappati, zero perdite di handshake.

---

### PRG-T07 — Ripristino da riavvio a caldo e a freddo

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Produzione in corso con 10 pezzi in coda; riavvio a caldo. | La coda viene ripristinata da `SP_RetainMgr` oppure dichiaratamente azzerata (documentare la scelta); nessuno stato inconsistente. |
| 2 | Riavvio a freddo. | `PRG_SP_ConfigInit` rieseguito; configurazione di default o ricetta caricata. |
| 3 | Verificare i contatori KPI. | Valori di fabbrica oppure ripristinati: coerenti con la policy di persistenza. |
| 4 | Ripartire la produzione. | Nessun blocco; ripartenza pulita. |

**Criterio:** nessuno stato inconsistente dopo i riavvii.

---

### PRG-T08 — Timing deterministico dei task (misura estesa)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Registrare per 24 h (o 1 h accelerata) i tempi di esecuzione di ciascun task. | Statistiche: media, max, n. superamenti watchdog. |
| 2 | Verificare il jitter. | Fast: max < 6 ms; Main: max < 30 ms; Svc: max < 300 ms. |
| 3 | Verificare la drift dell orologio. | `udiTickMs` e `stRtc` coerenti (nessuna drift anomala). |

**Criterio:** tempi nei limiti per tutta la durata.

---

### PRG-T09 — Interazione HMI completa (tutti i comandi)

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Eseguire la sequenza: Start → Pause → Resume → Stop → Reset. | Ogni comando ha effetto entro 1 ciclo del task Main; stati FSM coerenti. |
| 2 | Comandi in Manuale (`bAuto=FALSE`). | I comandi manuali funzionano; l automatico è bloccato. |
| 3 | Comandi durante un allarme attivo. | Comportamento documentato (stop prioritario); nessun movimento incondizionato. |
| 4 | Comandi rapidi ripetuti (debounce). | Nessuna azione doppia. |

**Criterio:** tutti i comandi gestiti in modo deterministico.

---

### PRG-T10 — Riconciliazione contatori end-to-end

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Far gestire N=100 pezzi in CFG 2. | `udiFed = 100`. |
| 2 | Conteggiare a fine run. | `udiPick + scarti + pezzi_in_coda = udiFed`; `uiGood + uiNo = udiPick`; vassoi: `uiDone` coerente con le posa. |
| 3 | Verificare gli OEE. | `rOee = rA x rP x rQ` entro ±0.001. |
| 4 | Ripetere con doppioni attivi (overlap scatti). | `udiDup` conteggiato a parte: `udiFed` NON include i doppioni. |

**Criterio:** bilancio di massa dei contatori esatto.

---

## Sezione 6 — Test di Integrazione Progressiva CFG 1 .. CFG 8 (INT-1 .. INT-8)

Le configurazioni di sistema attivano progressivamente i sottoinsiemi funzionali. Ogni configurazione ha: obiettivo, setup esatto (parametri da impostare), procedura passo-passo, risultati attesi quantitativi e criterio. **Si avanza solo con tutti i test precedenti PASS.**

---

### INT-1 — CFG 1 — Nastro singolo statico, posa fissa

**Obiettivo:** Verifica della catena base: alimentazione → tracking → robot singolo → posa in punto fisso.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| stSys.eMode | Simulated | Simulazione completa |
| astRob[1].bUsed | TRUE | Solo robot 1 |
| astRob[2..4].bUsed | FALSE | Robot residui disabilitati |
| stCam[1].bUsed | TRUE | Solo camera 1 |
| stCam[2].bUsed | FALSE | Camera 2 off |
| stConv[1].rBeltSpeed | 450.0 | Velocità base |
| LoadBalancer.eStrat | Greedy | Un solo robot: strategia irrilevante |
| PatternGen | OFF | Posa fissa, nessun pattern |
| bResilience | FALSE | Nessuna resilienza richiesta |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Avviare con `bStart=TRUE`. | FSM → Running. |
| 2 | Alimentare 20 pezzi (simulatore cam 1, uno ogni 3 s). | 20 pezzi tracciati (`udiFed=20`). |
| 3 | Osservare i cicli robot. | 20 prese e 20 pose complete; `stOut.udiPick=20`, contatore place=20. |
| 4 | Verificare la posa. | Tutti i pezzi nella stessa posizione fissa (offset < 1 mm simulato). |
| 5 | Verificare i tempi. | Ciclo medio robot registrato in `stOut.uiCycleMs`. |
| 6 | Fermare con `bStop=TRUE`. | Sistema → Idle a fine ciclo; nessun pezzo perso in coda. |

**Criterio INT-1:** PASS se: 20/20 pezzi gestiti, nessun allarme, contatori coerenti.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-2 — CFG 2 — Più tipi di prodotto (fino a 32) + posa in vassoio

**Obiettivo:** Verifica della gestione tipi prodotto e del pattern di posa su vassoio.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| PatternGen.stCfg | Pattern 4×3 vassoio | 12 posizioni |
| ProdType[1..3] | 3 tipi distinti | Diversi per peso/dimensioni |
| MixType | ON | Sequenza mista |
| BatchMgr | Batch da 12 battute | Un vassoio pieno |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Avviare con mix di 3 tipi. | I pezzi vengono riconosciuti per tipo dalla camera. |
| 2 | Verificare la classificazione. | `GetNextItem` riporta `iTyp` corretto per ogni pezzo. |
| 3 | Eseguire un vassoio (12 posa). | Gli slot vengono riempiti secondo il pattern; `NotifyPlaced` ×12. |
| 4 | Verificare il mix. | La sequenza dei tipi sul vassoio rispetta `MixType`. |
| 5 | Al termine. | `stStat.bComplete=TRUE` per il batch; allarme di vassoio pieno gestito. |

**Criterio INT-2:** PASS se: tipi corretti, 12/12 posa, batch completato.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-3 — CFG 3 — Multi-camera con zone di lavoro separate

**Obiettivo:** Verifica della mappatura camere → nastri e delle zone mutualmente esclusive.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| stCam[1].stCfg.rMapY | [nastro 1] | Mappa Y camera 1 |
| stCam[2].stCfg.rMapY | [nastro 2] | Mappa Y camera 2 |
| ZoneGuard | Zone 1 e 2 | Separate |
| astRob[1].zone | Zona 1 |  |
| astRob[2].zone | Zona 2 |  |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Avviare con 2 camere attive. | Entrambe le camere scattano e alimentano le rispettive code. |
| 2 | Verificare la mappatura Y. | Gli item della cam 1 finiscono sulla coda 1, cam 2 sulla coda 2. |
| 3 | Verificare le zone. | Robot 1 e 2 operano sulle rispettive zone; `PairSharesZone(1,2)=FALSE`. |
| 4 | Forzare un pezzo della cam 2 nella zona 1 (mapping errato). | Il pezzo viene rifiutato o instradato correttamente (verificare il comportamento atteso del driver). |
| 5 | Conteggi. | `udiFed` separati per coda; nessun incrocio. |

**Criterio INT-3:** PASS se: mappatura corretta, zone separate, nessun incrocio di code.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-4 — CFG 4 — 2 robot che lavorano sullo stesso nastro (load balancing)

**Obiettivo:** Verifica del `SP_LoadBalancer` e della condivisione coda.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| astRob[1..2].bUsed | TRUE | Due robot |
| LoadBalancer.eStrat | Balanced | Bilanciamento attivo |
| stConv[1].rBeltSpeed | 600.0 |  |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Alimentare 30 pezzi. | I pezzi vengono distribuiti ai due robot. |
| 2 | Verificare il bilanciamento. | Conteggi pick: 15±1 per robot. |
| 3 | Verificare la prossimità. | Nessun pezzo assegnato a un robot mentre l'altro è più vicino e libero (per Balanced: solo bilanciamento). |
| 4 | Fermare il robot 2 (`MarkFault`). | Tutti i pezzi al robot 1; nessuna perdita. |
| 5 | Ripristinare robot 2. | Bilanciamento ripreso. |

**Criterio INT-4:** PASS se: 30/30 pezzi, ripartizione 15±1, failover del robot 2 gestito.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-5 — CFG 5 — 4 robot, 4 zone, collision avoidance attivo

**Obiettivo:** Verifica di `SP_Collision` e `SP_ZoneGuard` con tutti i robot.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| astRob[1..4].bUsed | TRUE | Tutti i robot |
| ZoneGuard | 4 zone |  |
| Collision.stCfg.rSepSlow | 450.0 | mm |
| Collision.stCfg.rSepStop | 250.0 | mm |
| LoadBalancer.eStrat | Organic |  |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Alimentare 40 pezzi distribuiti. | Tutti i robot partecipano. |
| 2 | Monitorare le distanze TCP-TCP. | Nessuna distanza < 250 mm; rallentamenti fra 250 e 450. |
| 3 | Verificare le zone. | `bOccupied` coerenti; nessun deadlock (tutti i job completati). |
| 4 | Forzare un incrocio (traiettorie incrociate). | `bSlowRob`/`bStopRob` intervengono; nessuna collisione simulata. |
| 5 | Conteggi. | 40/40 pezzi gestiti. |

**Criterio INT-5:** PASS se: 40/40, zero collisioni, zero deadlock.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-6 — CFG 6 — Belt-to-belt (presa su un nastro, posa su un altro)

**Obiettivo:** Verifica del tracking multi-nastro e dei frame (`SetBeltFrames`).

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| stConv[1].rBeltSpeed | 450.0 | Nastro sorgente |
| stConv[2].rBeltSpeed | 300.0 | Nastro destinazione |
| Robot.stCfg.bBeltToBelt | TRUE |  |
| SetBeltFrames | frame 1 e 2 |  |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Alimentare pezzi sul nastro 1. | Presa in tracking sul nastro 1. |
| 2 | Verificare la posa. | Pezzi depositati sul nastro 2 in posizione nota rispetto al frame del nastro 2. |
| 3 | Verificare la compensazione. | Errore di posa sul nastro 2 < 2 mm simulati. |
| 4 | Cambiare la velocità del nastro 2 a 600 mm/s. | La compensazione si adatta senza errori sistematici. |
| 5 | Conteggi. | Nessun pezzo perso fra i due nastri. |

**Criterio INT-6:** PASS se: errori di posa nei limiti a entrambe le velocità.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-7 — CFG 7 — Multi-layer (pallet multipli, avanzamento livelli)

**Obiettivo:** Verifica della progressione multi-livello di `SP_BatchMgr`/`SP_PatternGen`.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| BatchMgr.stDef.iLayers | 2 | Due livelli |
| PatternGen | Pattern 4×3 |  |
| stCfg.bPalletStatic | TRUE | Pallet statico |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Avviare il batch. | Livello 1: 12 posa secondo pattern. |
| 2 | Al termine del livello 1. | Passaggio automatico al livello 2 (`iLayer=2`). |
| 3 | Completare il livello 2. | `bComplete=TRUE`; conteggio totale 24 posa. |
| 4 | Verificare i conteggi. | `stStat.uiDone=24`. |

**Criterio INT-7:** PASS se: 24/24 posa, transizione di livello automatica.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

### INT-8 — CFG 8 — Full speed + fault injection combinata

**Obiettivo:** Configurazione massima: 1200 mm/s, resilienza, collisioni, doppioni, 4 robot.

**Setup esatto (impostare prima di ogni test):**

| Parametro | Valore | Note |
|---|---|---|
| stConv[1..2].rBeltSpeed | 1200.0 | Velocità massima |
| stCam[1..2].stCfg.tInterval | T#100ms | Scatti rapidi |
| bResilience | TRUE |  |
| LoadBalancer.eStrat | Balanced |  |
| GC_DUP_TOL_MM | 25.0 | Filtro doppioni attivo |

**Procedura passo-passo:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Alimentare 100 pezzi in 5 minuti (overlap di scatti inclusi). | `udiFed=100`, `udiDup` > 0 se gli overlap sono simulati, `uiTracked` mai > 64. |
| 2 | Eseguire tutti i test FT della Sezione 7 in questa configurazione. | Vedi Sezione 7. |
| 3 | Verificare le prestazioni. | Throughput ≥ soglia target (vedi Sezione 8 per il benchmark). |
| 4 | Verificare i contatori finali. | `udiPick + scarti = udiFed`; nessun pezzo fantasma. |

**Criterio INT-8:** PASS se: 100/100 gestiti, fault tollerati, throughput nel target.

**Metriche da registrare per questa configurazione:**

| Metrica | Unita | Valore atteso | Valore misurato |
|---|---|---|---|
| Throughput | pezzi/min | >= target di fase | — |
| Tempo ciclo medio robot | ms | <= baseline + 10% | — |
| Pick persi | pezzi | 0 | — |
| Aborti volo | conteggio | 0 (tranne test dedicati) | — |
| Allarmi anomali | conteggio | 0 | — |


**Gate GO/NO-GO:** il passaggio alla configurazione successiva e consentito solo con tutti i passi PASS e le metriche registrate.

---

## Sezione 7 — Fault Injection e Stress Test (FT-01 .. FT-25)

Test distruttivi controllati. **Prerequisito di sicurezza [HW]:** area libera, valvole aria escludibili, personale fuori dalla cella. In simulazione eseguire tutto tranne dove indicato [HW]. Ogni test va eseguito da uno stato Running noto e va verificato il ripristino a fine test.

### FT-01 — E-Stop durante il volo del robot  [[HW/Sim]]

**Precondizioni:** Sistema in Running, robot in `MoveToPlace` con pezzo.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Premere E-Stop. | Movimenti fermati entro 1 ciclo; valvole: `AbortAll`; FSM → Emergency. |
| 2 | Verificare il pezzo. | Il pezzo è trattenuto (o perso in modo sicuro): nessun movimento incontrollato. |
| 3 | Rilasciare E-Stop e `bReset=TRUE`. | FSM → Idle; ripartenza possibile con `bStart`. |
| 4 | Conteggi. | Il pezzo interrotto risulta `Picked` e non `Placed`: verificare gestione a ripartenza. |

**Criterio FT-01:** STOP entro 1 ciclo del task; ripristino deterministico.

---

### FT-02 — Stop di emergenza a nastro a piena velocità  [[HW]]

**Precondizioni:** Nastro a 1200 mm/s con pezzi in coda.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | E-Stop. | Nastro fermo entro la distanza di sicurezza dei drive; pezzi non persi dal tracking (le posizioni restano coerenti con l'encoder fermo). |
| 2 | Ripristino e ripartenza. | Il tracking riprende correttamente: nessun doppione spurio, nessun pezzo fantasma. |

**Criterio FT-02:** Nessuna perdita di coerenza del tracking.

---

### FT-03 — Perdita di un robot in produzione (resilience ON)  [Sim]

**Precondizioni:** `bResilience=TRUE`, 2 robot attivi, job in corso.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `MarkFault(2)` durante il volo. | Il job del robot 2 viene riassegnato/annullato; `OnRobotLoss(2)` eseguito. |
| 2 | Verificare la migrazione. | Il carico/camere del robot 2 migrano ai robot residui (o il pezzo resta in coda per la ripresa). |
| 3 | Verificare la produzione. | Il sistema continua con il robot 1: nessun blocco totale. |
| 4 | Ripristinare il robot 2. | Rientro automatico alla coda successiva. |

**Criterio FT-03:** Produzione continua; nessun pezzo perso.

---

### FT-04 — Perdita di un robot (resilience OFF)  [Sim]

**Precondizioni:** `bResilience=FALSE`.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | `MarkFault(2)`. | FSM sistema → Emergency o stato di fermo dedicato; allarme generato. |
| 2 | `ClearFault(2)` + reset. | Ripristino a Idle. |

**Criterio FT-04:** Fermo sicuro; ripristino documentato.

---

### FT-05 — Camera che non risponde  [Sim]

**Precondizioni:** Camera 1 in scatto periodico.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Forzare `tTimeout` scaduto ×5. | `stOut.bTimeout=TRUE` ×5; allarmi camera; nessun blocco del tracking per gli altri pezzi. |
| 2 | Ripristinare la camera. | Ripresa automatica senza reset. |

**Criterio FT-05:** Nessun blocco del sistema; allarmi corretti.

---

### FT-06 — Dati camera corrotti  [Sim]

**Precondizioni:** Inviare righe malformate (FT-DRV1/2).

**Procedura:** Nessun pezzo spurio inserito in coda; `GetError` corretto.
**Criterio FT-06:** Zero pezzi fantasma.

---

### FT-07 — Presa a vuoto (nessun pezzo sul cup)  [Sim/HW]

**Precondizioni:** `GripStart` senza pezzo: feedback OFF.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Eseguire la prenda. | `FbkOk=FALSE`; retry fino a `iRetries`. |
| 2 | Retry esauriti. | Il pezzo resta in coda o viene marcato scarto; job chiuso correttamente. |
| 3 | Verificare i contatori. | Nessun `udiPick` incrementato per la presa fallita. |

**Criterio FT-07:** Nessun pick fantasma.

---

### FT-08 — Perdita del pezzo in volo  [Sim]

**Precondizioni:** Presa valida, poi feedback che si spegne in `Depart`.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Spegnere il feedback durante il volo. | Rilevamento perdita; `udiAbortFlight` incrementa. |
| 2 | Verificare il target. | La posa viene annullata o il pezzo sostituito: nessuna posa di pezzo assente. |
| 3 | Ripristino. | Il sistema riparte senza intervento manuale (se resilience) o con reset. |

**Criterio FT-08:** Nessuna posa di pezzo inesistente.

---

### FT-09 — Feedback parziale (1 ventosa su 2)  [Sim]

**Precondizioni:** Cluster di 2 pezzi, 1 feedback OFF.

**Procedura:** GripEval: il job degrada a monopezzo; `FirstFailedPlace` identifica la ventosa vuota; la posa procede per il pezzo presente.
**Criterio FT-09:** Pezzo presente posato; pezzo assente non "posato".

---

### FT-10 — Nastro che si ferma con pezzi in coda  [Sim]

**Precondizioni:** `bEnable=FALSE` sul nastro con 5 pezzi.

**Procedura:**

| Passo | Azione | Risultato atteso |
|---|---|---|
| 1 | Fermare il nastro. | I pezzi restano tracciati; il robot arresta le prese (nessun inseguimento). |
| 2 | Riavviare il nastro. | Il tracking riprende con le posizioni corrette. |

**Criterio FT-10:** Coerenza del tracking mantenuta.

---

### FT-11 — Encoder fermo/fuori scala  [Sim]

**Precondizioni:** Forzare `rEnc` costante o 1e9.

**Procedura:** Allarme encoder; sistema in fermo sicuro; nessuna posizione NaN.
**Criterio FT-11:** Allarme corretto.

---

### FT-12 — Timeout di inseguimento nastro  [Sim]

**Precondizioni:** Distanza target-TCP crescente oltre il limite.

**Procedura:** Job annullato in sicurezza; `udiAbortFlight` incrementa.
**Criterio FT-12:** Nessun movimento fuori finestra.

---

### FT-13 — E-Stop+reset ripetuti ×20  [Sim/HW]

**Precondizioni:** Ripetere FT-01 20 volte.

**Procedura:** Nessun deadlock; FSM sempre ripristinabile.
**Criterio FT-13:** 20/20 ripristini.

---

### FT-14 — Allarmi multipli simultanei  [Sim]

**Precondizioni:** Generare 10 allarmi insieme.

**Procedura:** Tutti registrati; `AckAll` li gestisce.
**Criterio FT-14:** 10/10 presenti.

---

### FT-15 — Code piene (64 item)  [Sim]

**Precondizioni:** Alimentare 70 pezzi rapidamente.

**Procedura:** Saturazione gestita (`ErrFull`); nessun crash; pezzi in eccesso scartati con allarme.
**Criterio FT-15:** Nessun blocco.

---

### FT-16 — Log/allarmi saturi  [Sim]

**Precondizioni:** 300 log + 70 allarmi.

**Procedura:** Gestione circolare; nessuna perdita di dati recenti.
**Criterio FT-16:** Stabilità.

---

### FT-17 — Export ricetta durante la produzione  [Sim]

**Precondizioni:** Avviare `SP_RecipeMgr.ExportBegin` in Running.

**Procedura:** Nessun blocco dei task; file coerente.
**Criterio FT-17:** Produzione continua.

---

### FT-18 — Import ricetta corrotta  [Sim]

**Precondizioni:** Righe corrotte (FT-RCP1).

**Procedura:** Errori con numero riga; configurazione coerente.
**Criterio FT-18:** Nessun crash.

---

### FT-19 — Perdita alimentazione simulata (retain)  [Sim]

**Precondizioni:** Salvare, corrompere un campo, riavviare.

**Procedura:** `Validate()=FALSE`; `RestoreDefaults`/`SetRecipe` ripristinano.
**Criterio FT-19:** Ripristino verificato.

---

### FT-20 — Perdita socket camera  [Sim]

**Precondizioni:** Chiudere il socket.

**Procedura:** `RxOverflow`/timeout gestiti; ripristino automatico alla riconnessione.
**Criterio FT-20:** Nessun blocco.

---

### FT-21 — Comandi HMI contrastanti  [Sim]

**Precondizioni:** `bStart`+`bStop`+`bReset` insieme.

**Procedura:** Priorità deterministica (FT-SYS1); stato coerente.
**Criterio FT-21:** Comportamento documentato.

---

### FT-22 — Doppioni aggressivi (scatti ogni 20 ms a 1200 mm/s)  [Sim]

**Precondizioni:** Overlap continuo di scatti.

**Procedura:** `udiDup` cresce; `uiTracked` stabile; nessun job duplicato.
**Criterio FT-22:** Zero job duplicati.

---

### FT-23 — Stress 8 nastri + 4 robot + 2 camere per 1 h  [Sim]

**Precondizioni:** Carico massimo.

**Procedura:** `udiStatDrop=0`; tempi di task nei limiti; memoria stabile.
**Criterio FT-23:** Stabilità 1 h.

---

### FT-24 — Sovraccarico task Fast  [Sim]

**Precondizioni:** Aggiungere carico fino a jitter anomalo.

**Procedura:** Watchdog e allarme; nessuna corruzione dati.
**Criterio FT-24:** Allarme corretto.

---

### FT-25 — Fault multi-robot (2 robot in fault insieme)  [Sim]

**Precondizioni:** `MarkFault(1)` e `MarkFault(2)` insieme.

**Procedura:** Con resilience: produzione con i robot residui; senza: Emergency.
**Criterio FT-25:** Comportamento coerente con FT-03/04.

---

## Sezione 8 — Benchmark "Prima vs Dopo" per le 14 funzionalità avanzate (BM-01 .. BM-14)

Protocollo di misura per dimostrare il superamento di MotoPick 4. Per ogni funzionalità: **Baseline (Prima)** = misura sul sistema attuale; **Dopo** = misura con la funzionalità implementata; **Stimolo** = scenario riproducibile di prova. Le misure vanno registrate nel formato della tabella 8.1.

### 8.1 Protocollo di misura comune

1. Eseguire ogni scenario **3 volte** e riportare media ± deviazione standard.
2. Usare sempre la stessa configurazione di riferimento: `CFG 8` ridotta a 2 robot (per confrontabilità) o la configurazione di produzione target.
3. Strumenti di misura: `GVL_SP_Rtc.udiTickMs` (tempistiche), contatori `SP_Stats`/`stOut` (qualità), WT dedicate.
4. Registrare: metrica, unità, valore baseline, valore dopo, delta %, esito.

| Metrica comune | Unità | Come si misura |
|---|---|---|
| Throughput | pezzi/min | `stStats.uiFeedPerMin` su finestra di 10 minuti. |
| Tempo ciclo medio | ms | `stSys.udiCycleMs` (media di 100 cicli). |
| Pick persi | pezzi | `udiFed − (udiPick + scarti)` a fine run. |
| Aborti volo | conteggio | `stSys.udiAbortFlight` a fine run. |
| Doppioni gestiti | conteggio | `udiDup` a fine run. |
| Dead time inter-ciclo | ms | Delta fra fine `Retreat` e prossima offerta job (log a 2 ms). |


### BM-01 — In-Flight Part-Drop Recovery (Recupero pezzo perso in volo)

**Stimolo di misura:** Lanciare un volo e togliere il pezzo (feedback OFF in `Depart`): misurare quanti viaggi vuoti vengono comunque percorsi e quanti vassoi escono incompleti.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Viaggi vuoti: N; vassoi incompleti: N. |
| Obiettivo (Dopo) | Viaggi vuoti: 0 (abort + rilascio slot); vassoi incompleti: 0. |
| Cosa dimostra | Nessun pezzo perso → nessuna posa "fantasma"; slot del vassoio rilasciato e ripreso dal pezzo successivo. |

**Procedura BM-01:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-01:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-02 — Time-of-Flight Intercept (Intercettazione con stima tempo di volo)

**Stimolo di misura:** Alimentare pezzi a 1200 mm/s con ultima finestra di prenda vicina a `rRangeFrom`: contare le prese tentate su pezzi irraggiungibili.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Tentativi falliti: N (pezzi oltre il punto di non ritorno). |
| Obiettivo (Dopo) | Tentativi falliti: 0 (pezzi scartati prima dell'offerta job). |
| Cosa dimostra | La stima `t_tof` evita offerte disperate; throughput invariato o migliore. |

**Procedura BM-02:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-02:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-03 — Simmetria rotazionale prodotto (Rotazione polso minima)

**Stimolo di misura:** Prodotti a simmetria 2/4/99 (es. bottiglia circolare): misurare la rotazione media del polso Rz per prenda.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Rotazione media: X° (sempre ≤ 180°). |
| Obiettivo (Dopo) | Rotazione media: ≤ X°/2 per simmetria 2, ≤ X°/4 per simmetria 4, ≈0 per circolari. |
| Cosa dimostra | Tempo di prenda ridotto della componente rotazione. |

**Procedura BM-03:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-03:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-04 — Scoring multi-criterio (Selezione pezzo ottimale)

**Stimolo di misura:** Due pezzi equiprobabili: uno urgente ma lontano in Y, l'altro vicino in TCP: misurare quale viene scelto e il tempo di ciclo.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Scelta: sempre il più vicino in X (o FIFO). |
| Obiettivo (Dopo) | Scelta: minimo di una funzione combinata (urgenza + distanza TCP). |
| Cosa dimostra | Tempo di ciclo medio ridotto; nessun pezzo esce dalla finestra. |

**Procedura BM-04:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-04:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-05 — Trigger latency compensation + FIFO latch (Correzione del latch trigger)

**Stimolo di misura:** Trigger di riferimento noto (posizione esatta): misurare l'errore di stima `rEncCap` fra trigger e posa.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Errore sistematico: `tTrigDelay × v` (es. 40 ms × 450 = 18 mm). |
| Obiettivo (Dopo) | Errore: < 1 mm (compensato) anche con 4 trigger ravvicinati (FIFO). |
| Cosa dimostra | Precisione di prenda migliorata; nessun trigger perso. |

**Procedura BM-05:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-05:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-06 — Smooth belt pacing + slew limiter (Rampa di velocità nastro)

**Stimolo di misura:** Pezzi a intervalli irregolari: misurare l'escursione di `rReqFactor` per ciclo.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Escursione: fino a 1.0→0.0 in un ciclo (scalino). |
| Obiettivo (Dopo) | Escursione: rampa lineare fra `rSlowAhead` e `rStopAhead`; variazione per ciclo ≤ slew configurato. |
| Cosa dimostra | Nessuno scalino meccanico; usura drive ridotta. |

**Procedura BM-06:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-06:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-07 — Active Reject + Digital Twin avanzato (Scarto attivo NG e simulazione completa)

**Stimolo di misura:** Prodotti NG (`bReject=TRUE` nel catalogo): misurare il destino degli item NG e il tempo di test in simulazione.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | NG: lasciati sul nastro o ignorati. |
| Obiettivo (Dopo) | NG: instradati su `p3RejectBin` in modo esplicito. |
| Cosa dimostra | Zero NG verso i vassoi; test end-to-end senza HW con simulazione fotocellule/overlap. |

**Procedura BM-07:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-07:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-08 — Look-Ahead Job Pre-Fetch (Zero-Tick Handover)

**Stimolo di misura:** Misurare il tempo fra fine `Retreat` del ciclo N e l'offerta del ciclo N+1 (log a 2 ms).

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Dead time: 20-40 ms (1-2 tick del task Main). |
| Obiettivo (Dopo) | Dead time: ≤ 2 ms (prefetch durante il `Retreat` finale). |
| Cosa dimostra | Throughput +5-10% tipico; nessun cambio di semantica dei job. |

**Procedura BM-08:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-08:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-09 — Valve pre-actuation + fly-by blending (Anticipo valvole e blending traiettorie)

**Stimolo di misura:** Misurare il tempo di presa (da contatto a feedback) e il tempo di percorrenza arco.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Tempo presa: `tGrip` pieno; arco: traiettoria a spigoli. |
| Obiettivo (Dopo) | Tempo presa: `tGrip − tPreGripMs`; arco: blendato entro `rBlendRad`. |
| Cosa dimostra | Ciclo ridotto del 3-8% tipico; presa sicura verificata dal feedback. |

**Procedura BM-09:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-09:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-10 — Catalogo prodotti 2.5D (Velocità per tipo)

**Stimolo di misura:** Due tipi: fragile (vel_scale 0.6) e robusto (1.0): misurare la velocità TCP a vuoto e carico.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Velocità unica per tutti i prodotti. |
| Obiettivo (Dopo) | Velocità variabile per tipo; 100% a vuoto. |
| Cosa dimostra | Tempo a vuoto ridotto; fragile trattato correttamente. |

**Procedura BM-10:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-10:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-11 — Safe traverse dinamico (Altezza di transito)

**Stimolo di misura:** Prodotti alti (scatole 300 mm) con traversate sul nastro: misurare gli urti simulati.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Urti simulati: N (Z fissa). |
| Obiettivo (Dopo) | Urti: 0 (`rZSafeTraverse` dinamico). |
| Cosa dimostra | Nessuna collisione con il carico. |

**Procedura BM-11:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-11:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-12 — Singulation guard (Distanza minima gripper)

**Stimolo di misura:** Pezzi distanti 30 mm (> 25 mm dup, < 50 mm gripper): misurare le prese tentate su pezzi adiacenti.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Tentativi con interferenza gripper: N. |
| Obiettivo (Dopo) | Tentativi: 0 (ordinamento/scarto per `rGripClearance`). |
| Cosa dimostra | Nessuna collisione gripper-gripper/pezzo. |

**Procedura BM-12:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-12:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-13 — Adaptive load balancing (Bypass quota urgenza)

**Stimolo di misura:** Un robot con coda lunga e pezzi in uscita (urgenti): misurare i pezzi usciti fuori finestra.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Pezzi fuori finestra: N (quota bilanciata cieca). |
| Obiettivo (Dopo) | Pezzi fuori finestra: 0 (bypass quota per `rNearOff < rUrgentDist`). |
| Cosa dimostra | Nessun pezzo perso per bilanciamento. |

**Procedura BM-13:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-13:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### BM-14 — Bottleneck analyzer (Diagnostica tempo reale)

**Stimolo di misura:** Sovraccaricare un sottosistema (es. camera lenta): misurare il tempo per identificare il collo di bottiglia.

| Voce | Contenuto |
|---|---|
| Baseline (Prima) | Diagnosi: manuale, su log storici. |
| Obiettivo (Dopo) | Diagnosi: `ET_SP_Bottleneck` in tempo reale per robot (pick/place/wait). |
| Cosa dimostra | Intervento mirato; miglioramento del throughput documentato. |

**Procedura BM-14:**

1. Configurare lo scenario sul sistema attuale (codice base, funzionalità NON implementata).
2. Eseguire 3 run da 10 minuti; registrare la metrica nella tabella 8.1.
3. Implementare la funzionalità (o abilitarla con flag di configurazione).
4. Ripetere le 3 run con lo scenario identico.
5. Compilare la riga di confronto (media ± σ, delta %).

**Criterio BM-14:** PASS se il valore Dopo rispetta l'obiettivo senza degradare le metriche comuni (throughput, pick persi = 0).

---

### 8.2 Tabella di sintesi benchmark (compilare a fine campagna)

| ID | Funzionalità | Metrica | Prima (media±σ) | Dopo (media±σ) | Delta % | Esito |
|---|---|---|---|---|---|---|
| BM-01 | In-Flight Part-Drop Recovery | — | — | — | — | — |
| BM-02 | Time-of-Flight Intercept | — | — | — | — | — |
| BM-03 | Simmetria rotazionale prodotto | — | — | — | — | — |
| BM-04 | Scoring multi-criterio | — | — | — | — | — |
| BM-05 | Trigger latency compensation + FIFO latch | — | — | — | — | — |
| BM-06 | Smooth belt pacing + slew limiter | — | — | — | — | — |
| BM-07 | Active Reject + Digital Twin avanzato | — | — | — | — | — |
| BM-08 | Look-Ahead Job Pre-Fetch | — | — | — | — | — |
| BM-09 | Valve pre-actuation + fly-by blending | — | — | — | — | — |
| BM-10 | Catalogo prodotti 2.5D | — | — | — | — | — |
| BM-11 | Safe traverse dinamico | — | — | — | — | — |
| BM-12 | Singulation guard | — | — | — | — | — |
| BM-13 | Adaptive load balancing | — | — | — | — | — |
| BM-14 | Bottleneck analyzer | — | — | — | — | — |


---

## Sezione 9 — Collaudo su macchina reale (HW-01 .. HW-10)

Prerequisiti: test di simulazione tutti PASS; DPI e procedure di sicurezza del cliente; aria compressa regolata; video-camere reali configurate.
### HW-01 — Verifica I/O e cablaggio

**Procedura:** Confrontare `Hardware/HW_IO_Map_IT-EN.md` con il punto per punto: ogni ingresso/uscita forzato e verificato.
**Criterio:** Mappatura 1:1; nessun canale scambiato.

### HW-02 — Verifica encoder e misure nastro

**Procedura:** Trascinare il nastro a mano di 1000 mm (misura laser): confronto con l'encoder.
**Criterio:** Errore < 2 mm su 1000 mm.

### HW-03 — Calibrazione camera

**Procedura:** Eseguire `SP_Calib2D` con almeno 4 punti reali; verificare con 3 punti di controllo.
**Criterio:** Errore residuo < 1 mm sui punti di controllo.

### HW-04 — Taratura trigger

**Procedura:** Pezzo di riferimento a posizione nota: misurare `rEncCap` al trigger.
**Criterio:** Errore < 2 mm (compensazione BM-05 attiva).

### HW-05 — Verifica attrezzi e ventose

**Procedura:** Presa/posa manuale su tutti i cup.
**Criterio:** Feedback corretto per ogni ventosa.

### HW-06 — Verifica collisioni reali

**Procedura:** Moto ravvicinato controllato a velocità ridotta.
**Criterio:** Intervento di `SP_Collision` alla distanza tarata (±50 mm).

### HW-07 — Run a vuoto 30 minuti

**Procedura:** Ciclo completo senza pezzi.
**Criterio:** Nessun allarme; consumi/stati stabili.

### HW-08 — Run con pezzi reali (bassa velocità)

**Procedura:** 100 pezzi a 300 mm/s.
**Criterio:** 100/100 gestiti; qualità posa entro tolleranza cliente.

### HW-09 — Run a velocità nominale

**Procedura:** 100 pezzi alla velocità target.
**Criterio:** Throughput nel target; pick persi = 0.

### HW-10 — Prova di resilienza

**Procedura:** Distacco simulato di un robot/camera.
**Criterio:** Comportamento come FT-03/FT-05.

---

## Sezione 10 — Criteri di accettazione finale e tracciabilità

Il software si considera **rilasciabile** quando:

1. Tutti i test `UT-*` (Sezioni 1-2): PASS.
2. Tutti i test `FB-T*` e la matrice `M-*` (Sezioni 3-4): PASS.
3. Tutti i test `PRG-*` (Sezione 5) incluso il carico incrociato: PASS.
4. Tutti gli `INT-1..INT-8` (Sezione 6): PASS.
5. Tutti gli `FT-01..FT-25` (Sezione 7): PASS o con deviazioni documentate e approvate.
6. Benchmark `BM-01..BM-14` (Sezione 8): baseline completata; obiettivi "Dopo" raggiunti per le funzionalità rilasciate.
7. Collaudo `HW-01..HW-10` (Sezione 9): PASS.
8. Zero anomalie `BLOCKER`/`MAJOR` aperte in Appendice C.
9. `Recipes/SP_RecipeCheck.py` passa su tutte le ricette di progetto.
10. Documentazione allineata (`README_Package_IT-EN.md`, `00_TaskConfig_IT-EN.md`, `OPEN_POINTS_IT-EN.md`).

**Tracciabilità:** ogni riga del Registro Esiti deve essere collegata a: versione firmware (`GC_SP_VER_*`), commit del sorgente, ID test, operatore. Il registro completo va allegato al rilascio.

### 10.1 Modulo di firma di rilascio

| Ruolo | Nome | Data | Firma |
|---|---|---|---|
| Sviluppo |  |  |  |
| Verifica (QA) |  |  |  |
| Commissioning |  |  |  |
| Cliente/Qualità |  |  |  |


---

## Appendice A — Glossario

| Termine | Significato |
|---|---|
| FB | Function Block (IEC 61131-3), blocco funzionale con stato. |
| FUNCTION | Funzione pura senza stato (IEC 61131-3). |
| METHOD | Metodo di un FB (stile PLCopen), usa solo VAR/VAR_IN. |
| DUT | Data Unit Type (TYPE: STRUCT/ENUM) in foglio dati. |
| GVL | Global Variable List. |
| VAR_IN_OUT | Parametro di ingresso-uscita passato per riferimento: mai lasciato non assegnato. |
| Tracking | Inseguimento pezzi sul nastro tramite encoder e code. |
| Doppione | Stesso pezzo visto da due scatti ravvicinati della camera. |
| GC_DUP_TOL_MM | Tolleranza (mm) per la fusione dei doppioni (default 25 mm). |
| GripEval | Valutazione esito presa per ventosa (parziale/totalmente fallita). |
| Belt-to-belt | Presa da un nastro e posa su un altro nastro in movimento. |
| KPI | Key Performance Indicator (OEE, throughput, ciclo medio). |
| OEE | Overall Equipment Effectiveness = A × P × Q. |
| Fault injection | Test di iniezione guasti controllati. |
| Baseline | Misura di riferimento prima dell'implementazione di una funzionalità. |


## Appendice B — Template CSV per i log di benchmark

```csv
id;data_ora;operatore;ver_fw;config;metrica;unita;run1;run2;run3;media;sigma;note
BM-08;2026-10-13 10:00:00;MR;1.8.0;CFG8-2rob;dead_time_inter_ciclo;ms;2;2;3;2.33;0.47;baseline
```

## Appendice C — Registro anomalie (template)

| ID | Data | Test | Gravità (BLOCKER/MAJOR/MINOR) | Descrizione | Azione correttiva | Stato | Firma |
|---|---|---|---|---|---|---|---|
| AN-001 | | | | | | APERTA | |

## Appendice D — Checklist di importazione (73 fogli, ordine da `00_ImportOrder.st`)

Importare nell'ordine riportato; dopo ogni blocco di 10 fogli eseguire "Check all".

| N. | Foglio | Dimensione (righe) |
|---|---|---|
| 1 | 00_ImportOrder.st | 105 |
| 2 | 01_Common/DUT_SP_Enums_Common.st | 237 |
| 3 | 01_Common/DUT_SP_Structs_Common.st | 66 |
| 4 | 01_Common/FB_SP_AlarmMgr.st | 273 |
| 5 | 01_Common/FB_SP_Logger.st | 223 |
| 6 | 01_Common/FB_SP_MovAvg.st | 60 |
| 7 | 01_Common/FUN_SP_ByteCh.st | 31 |
| 8 | 01_Common/FUN_SP_Parse.st | 530 |
| 9 | 01_Common/FUN_SP_RtcToStr.st | 91 |
| 10 | 01_Common/FUN_SP_TickToRtc.st | 84 |
| 11 | 01_Common/FUN_SP_Utils.st | 302 |
| 12 | 01_Common/GVL_SP_Const.st | 79 |
| 13 | 02_Geometry/DUT_SP_Geometry.st | 71 |
| 14 | 02_Geometry/FB_SP_Calib2D.st | 209 |
| 15 | 02_Geometry/FUN_SP_Geometry.st | 195 |
| 16 | 03_Conveyor/DUT_SP_ConveyorTypes.st | 45 |
| 17 | 03_Conveyor/FB_SP_ConvDrive.st | 87 |
| 18 | 03_Conveyor/FB_SP_ConvEncoder.st | 64 |
| 19 | 03_Conveyor/FB_SP_Conveyor.st | 180 |
| 20 | 04_Vision/DUT_SP_VisionTypes.st | 84 |
| 21 | 04_Vision/FB_SP_DrvAscii.st | 379 |
| 22 | 04_Vision/FB_SP_DrvCognex.st | 120 |
| 23 | 04_Vision/FB_SP_DrvGeneric.st | 110 |
| 24 | 04_Vision/FB_SP_DrvKeyence.st | 119 |
| 25 | 04_Vision/FB_SP_Socket.st | 224 |
| 26 | 04_Vision/FB_SP_VisionCam.st | 415 |
| 27 | 04_Vision/FUN_SP_CamPreset.st | 90 |
| 28 | 04_Vision/GVL_SP_Vision.st | 21 |
| 29 | 05_Tracking/DUT_SP_TrkTypes.st | 93 |
| 30 | 05_Tracking/FB_SP_ItemQueue.st | 791 |
| 31 | 05_Tracking/FB_SP_TrkFeed.st | 308 |
| 32 | 05_Tracking/GVL_SP_Trk.st | 17 |
| 33 | 06_Pattern/DUT_SP_PatternTypes.st | 71 |
| 34 | 06_Pattern/FB_SP_BatchMgr.st | 327 |
| 35 | 06_Pattern/FB_SP_PatternGen.st | 418 |
| 36 | 07_LoadSharing/DUT_SP_ShareTypes.st | 52 |
| 37 | 07_LoadSharing/FB_SP_LoadBalancer.st | 343 |
| 38 | 07_LoadSharing/FB_SP_ZoneGuard.st | 173 |
| 39 | 08_Robot/DUT_SP_RobotTypes.st | 217 |
| 40 | 08_Robot/FB_SP_RobMotion.st | 503 |
| 41 | 08_Robot/FB_SP_Robot.st | 1548 |
| 42 | 08_Robot/FB_SP_ToolCtl.st | 462 |
| 43 | 09_Production/DUT_SP_SysTypes.st | 108 |
| 44 | 09_Production/FB_SP_Dispatch.st | 455 |
| 45 | 09_Production/FB_SP_Stats.st | 170 |
| 46 | 09_Production/FB_SP_System.st | 519 |
| 47 | 10_Persistence/DUT_SP_PersistTypes.st | 37 |
| 48 | 10_Persistence/FB_SP_FileIo.st | 219 |
| 49 | 10_Persistence/FB_SP_RecipeMgr.st | 713 |
| 50 | 10_Persistence/FB_SP_RetainMgr.st | 141 |
| 51 | 11_Simulation/FB_SP_SimCamera.st | 163 |
| 52 | 11_Simulation/FB_SP_SimConveyor.st | 41 |
| 53 | 12_Application/FUN_SP_RobCfgDefault.st | 139 |
| 54 | 12_Application/GVL_SP_Fw.st | 71 |
| 55 | 12_Application/GVL_SP_Hmi.st | 69 |
| 56 | 12_Application/GVL_SP_Inst.st | 42 |
| 57 | 12_Application/GVL_SP_Io.st | 41 |
| 58 | 12_Application/GVL_SP_Prod.st | 81 |
| 59 | 12_Application/GVL_SP_Rtc.st | 63 |
| 60 | 12_Application/GVL_SP_Sync.st | 62 |
| 61 | 12_Application/PRG_SP_ConfigInit.st | 1516 |
| 62 | 12_Application/PRG_SP_TaskFast.st | 816 |
| 63 | 12_Application/PRG_SP_TaskMain.st | 205 |
| 64 | 12_Application/PRG_SP_TaskSvc.st | 302 |
| 65 | 13_MultiGrip/DUT_SP_MultiGrip.st | 70 |
| 66 | 13_MultiGrip/FB_SP_GripPlanner.st | 410 |
| 67 | 13_MultiGrip/FUN_SP_ClusterMath.st | 99 |
| 68 | 14_Collision/DUT_SP_ColTypes.st | 71 |
| 69 | 14_Collision/FB_SP_Collision.st | 420 |
| 70 | 15_Professional/DUT_SP_ProTypes.st | 87 |
| 71 | 15_Professional/FB_SP_Maint.st | 187 |
| 72 | 15_Professional/FB_SP_Oee.st | 179 |
| 73 | 15_Professional/FB_SP_SelfTest.st | 210 |


## Appendice E — Tavole di riferimento rapido

### E.1 Costanti di progetto (`GVL_SP_Const.st` + `GVL_SP_Trk.st`)

| Costante | Valore | Uso |
|---|---|---|
| GC_ROBOTS | 4 | Numero massimo di robot |
| GC_FEEDS | 8 | Numero massimo di infeed/nastri |
| GC_CAMS | 2 | Numero massimo di camere |
| GC_TOOLS | 4 | Atrezzi per robot |
| GC_TYPES | 32 | Tipi di prodotto catalogabili |
| GC_CUPS | 4 | Ventose per attrezzo |
| GC_SEQ | 8 | Sequenze per attrezzo |
| GC_QUEUE | 64 | Profondita coda pezzi |
| GC_LAYERS | 4 | Livelli per batch |
| GC_PATT | 8 | Pattern configurabili |
| GC_PATT_SLOTS | 16 | Slot per pattern |
| GC_BATCHES | 8 | Batch simultanei |
| GC_LOG_N | 256 | Voci di log |
| GC_ALARM_N | 64 | Voci di allarme |
| GC_MOVAVG_N | 8 | Campioni media mobile |
| GC_ZONES | 4 | Zone di lavoro |
| GC_CALIB_PTS | 8 | Punti di calibrazione |
| GC_RATE_WIN | 10000 | Finestra feed rate (ms) |
| GC_ITEM_AGE_MS | 60000 | Scadenza pezzo in coda (ms) |
| GC_SPEED_MIN | 0.5 | Velocita minima ammessa (mm/s) |
| GC_DIST_EPS | 0.01 | Epsilon distanza (mm) |
| GC_ANG_EPS | 0.03 | Epsilon angolo (gradi) |
| GC_WIN_BEHIND | 20.0 | Finestra tracking dietro il sensore (mm) |
| GC_DUP_TOL_MM | 25.0 | Tolleranza doppioni (mm) |


### E.2 Inventario completo degli enumerati (valori attesi)

**`ET_SP_RetCode`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Done` := 0 | `Busy` := 1 | `Idle` := 2 |
| `ErrParam` := 10 | `ErrState` := 11 | `ErrFull` := 12 |
| `ErrEmpty` := 13 | `ErrNotFound` := 14 | `ErrCom` := 15 |
| `ErrIo` := 16 | `ErrBusy` := 17 | `ErrRange` := 18 |
| `NotImpl` := 99 |  |  |

**`ET_SP_LogLevel`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Debug` := 0 | `Info` := 1 | `Warn` := 2 |
| `Error` := 3 |  |  |

**`ET_SP_LogSource`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `System` := 0 | `Robot` := 1 | `Feed` := 2 |
| `Conveyor` := 3 | `Camera` := 4 | `Balancer` := 5 |
| `Batch` := 6 | `Persist` := 7 | `Simulation` := 8 |
| `User` := 9 |  |  |

**`ET_SP_SysState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Init` := 0 | `Standby` := 10 | `Starting` := 20 |
| `Running` := 30 | `Pausing` := 40 | `Paused` := 50 |
| `Resuming` := 60 | `Stopping` := 70 | `Stopped` := 80 |
| `Recovering` := 90 | `Fault` := 100 |  |

**`ET_SP_AckState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Inactive` := 0 | `Active` := 1 | `Acked` := 2 |

**`ET_SP_ItemState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Free` := 0 | `Tracked` := 10 | `Reserved` := 20 |
| `Picked` := 30 | `Held` := 40 | `Placed` := 50 |
| `Lost` := 60 | `TimedOut` := 70 |  |

**`ET_SP_RobState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Init` := 0 | `Homing` := 10 | `Ready` := 20 |
| `WaitJob` := 30 | `PlanPick` := 40 | `MoveApp` := 50 |
| `TrackPick` := 60 | `Grip` := 70 | `GripEval` := 71 |
| `Depart` := 80 | `PlanPlace` := 90 | `MovePlace` := 100 |
| `Place` := 110 | `Release` := 120 | `Retreat` := 130 |
| `Verify` := 140 | `Paused` := 150 | `Trial` := 160 |
| `Fault` := 170 |  |  |

**`ET_SP_Precision`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Exact` := 0 | `ZoneTight` := 1 | `ZoneWide` := 2 |

**`ET_SP_MatchMode`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Matched` := 0 | `Unmatched` := 1 | `Mixed` := 2 |

**`ET_SP_ShareStrategy`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Organic` := 0 | `Greedy` := 1 | `Balanced` := 2 |
| `Manual` := 3 |  |  |

**`ET_SP_GripMode`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Sync` := 0 | `Partial` := 1 | `Async` := 2 |

**`ET_SP_JobKind`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Pick` := 0 | `Place` := 1 | `PickPlace` := 2 |

**`ET_SP_BatchState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Idle` := 0 | `Running` := 10 | `Paused` := 20 |
| `Done` := 30 | `Aborted` := 40 |  |

**`ET_SP_PattTrig`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Distance` := 0 | `Sensor` := 1 | `BatchStart` := 2 |

**`ET_SP_VisionDrv`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Cognex` := 0 | `Keyence` := 1 | `GenericTCP` := 2 |
| `Simulated` := 3 |  |  |

**`ET_SP_VisionState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Offline` := 0 | `Connecting` := 10 | `Online` := 20 |
| `Triggered` := 30 | `Ready` := 50 | `Fault` := 90 |

**`ET_SP_TrigMode`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Distance` := 0 | `External` := 1 | `Interval` := 2 |
| `Manual` := 3 |  |  |

**`ET_SP_ConvDriveMode`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Analog` := 0 | `ServoAxis` := 1 | `External` := 2 |

**`ET_SP_SocketState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Closed` := 0 | `Connecting` := 10 | `Connected` := 20 |
| `Fault` := 90 |  |  |

**`ET_SP_FileState`** (01_Common/DUT_SP_Enums_Common.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `Closed` := 0 | `Opening` := 10 | `Open` := 20 |
| `Working` := 30 | `Closing` := 40 | `Fault` := 90 |

**`ET_SP_MvKind`** (08_Robot/DUT_SP_RobotTypes.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `None` := 0 | `Home` := 1 | `LinearAbs` := 2 |
| `TrackAbs` := 3 |  |  |

**`ET_SP_GripExec`** (13_MultiGrip/DUT_SP_MultiGrip.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `AsyncCup` := 0 | `SyncAll` := 1 |  |

**`ET_SP_ColAct`** (14_Collision/DUT_SP_ColTypes.st):

| Literal 1 | Literal 2 | Literal 3 |
|---|---|---|
| `None` := 0 | `WaitZone` := 1 | `SlowZone` := 2 |
| `SepSlow` := 3 | `SepStop` := 4 |  |

### E.3 Mappa codici di errore (`ET_SP_RetCode` via `FUN_SP_ErrorText`)

| Codice | Testo atteso | Uso tipico |
|---|---|---|
| Done | OK | Operazione completata |
| Busy | Busy | Risorsa occupata |
| Idle | Idle | Nessuna operazione in corso |
| ErrParam | Invalid parameter | Parametro fuori range |
| ErrState | Invalid state | Chiamata in stato non valido |
| ErrFull | Buffer full | Coda satura |
| ErrEmpty | Buffer empty | Coda vuota |
| ErrNotFound | Not found | ID/elemento assente |
| ErrCom | Communication error | Socket/driver |
| ErrIo | I/O error | File/disco |


### E.4 Soglie di sicurezza e tolleranze di collaudo

| Voce | Valore/Tolleranza | Note |
|---|---|---|
| Tolleranza numerica LREAL | ±0.001 | Salvo casi diversi indicati |
| Tolleranza conteggi | esatta | Nessun conteggio tollerato |
| Stringhe/enum/bool | esatte | Confronto letterale |
| Errore inseguimento nastro | < 2 mm | In simulazione e su HW |
| Errore posa belt-to-belt | < 2 mm |  |
| Tempo reazione E-Stop | ≤ 1 ciclo del task | Fast o Main secondo la catena |
| Jitter task Fast | max < 6 ms | Watchdog |
| Jitter task Main | max < 30 ms | Watchdog |
| Jitter task Svc | max < 300 ms | Watchdog |


## Appendice F — 25 sequenze Watch/Force rapide (diagnostica e riprova)

Sequenze preconfezionate da incollare nelle Watch Table per riprovare rapidamente un sottoinsieme funzionale dopo una modifica. Ogni sequenza termina con la riga di verifica.
| ID | Funzione | Sequenza | Verifica |
|---|---|---|---|
| SQ-01 | Avvio base | Forzare `stHmi.bStart=TRUE` → 1 ciclo → FALSE. | `stSys.eState=Running`, `bMotionPermit=TRUE`. |
| SQ-02 | Stop a fine ciclo | `stHmi.bStop=TRUE` → 1 ciclo → FALSE. | `eState=Stopping` poi `Idle` a fine ciclo corrente. |
| SQ-03 | E-Stop e ripristino | `stHmi.bEStop=TRUE` → verificare → FALSE → `bReset=TRUE`. | `eState=Emergency` poi `Idle`. |
| SQ-04 | Scatto camera forzato | `stCam[1].cmd.bTriggerNow=TRUE` → 1 ciclo → FALSE. | `stCam[1].stOut.uiItems>=1`. |
| SQ-05 | Pezzo sintetico in coda | `stCam[1].cmd.bInject=TRUE` con item noto. | `gastItemQ[1].stOut.uiTracked=1`. |
| SQ-06 | Doppione sintetico | Come SQ-05 due volte con `rEncCap` diverso e distanza < 25 mm. | `uiTracked=1`, `udiDup=1`. |
| SQ-07 | Pezzi distinti | Come SQ-05 due volte con distanza 40 mm. | `uiTracked=2`, `udiDup=1` (invariato). |
| SQ-08 | Reserve/Release | `Reserve(id,1)` → verificare → `Release(id)`. | `udiRes` 0→1→0. |
| SQ-09 | Rampa nastro | `stConv[1].rReqFactor` da 1.0 a 0.0 in 20 cicli. | `rBeltSpeed` segue la rampa senza scalini. |
| SQ-10 | Soglie pacing | Impostare pezzo a 165 mm da `rStopAhead`/`rSlowAhead` noti. | `FactorFor` = 0.5. |
| SQ-11 | Zona occupata | `Request(1,1)` → `Request(2,1)`. | Seconda richiesta negata. |
| SQ-12 | Collisione slow | Avvicinare due TCP simulati a 400 mm. | `bSlowRob=TRUE` su entrambi. |
| SQ-13 | Collisione stop | TCP a 240 mm. | `bStopRob=TRUE`. |
| SQ-14 | Allarme e ack | `AlarmMgr.Raise(...)` → `Ack(indice)`. | `uiUnack` 1→0. |
| SQ-15 | Log export | `Logger.LogInfo` ×3 → `ExportLine(1)`. | Riga CSV corretta. |
| SQ-16 | OEE rapido | Impostare tempi/noti → leggere `stOee`. | `rOee=rA*rP*rQ`. |
| SQ-17 | Self-test | Eseguire `SP_SelfTest` all avvio. | Tutti i sotto-test Done. |
| SQ-18 | Export ricetta | `RecipeMgr.ExportBegin/Next` fino a fine. | File completo. |
| SQ-19 | Import ricetta | `ImportLine` su ogni riga del file di SQ-18. | `GetError` vuoto. |
| SQ-20 | Checksum | `RetainMgr.ChkSum` → modificare un campo → `ChkSum`. | Valori diversi. |
| SQ-21 | GripEval parziale | Forzare 1 feedback OFF su cluster di 2. | Job degrada a monopezzo. |
| SQ-22 | Perdita in volo | Spegnere feedback in `Depart`. | `udiAbortFlight` incrementa. |
| SQ-23 | Perdita robot | `MarkFault(2)` con `bResilience=TRUE`. | Produzione continua. |
| SQ-24 | Batch multi-livello | `StartBatch` con 2 livelli. | Passaggio automatico a `iLayer=2`. |
| SQ-25 | Prefetch timing | Loggare fine `Retreat` e offerta job successivo. | Delta ≤ 20 ms (baseline BM-08). |


## Appendice G — Indice master di tutti i test (400+ ID)

Checklist unica di tracciabilita: ogni ID va firmato sul Registro Esiti.

| ID | Oggetto | Sezione |
|---|---|---|
| UT-F01 | Unit test FUNCTION `FUN_SP_Clamp` | Sez. 1 — 6 casi |
| UT-F02 | Unit test FUNCTION `FUN_SP_ClampI` | Sez. 1 — 4 casi |
| UT-F03 | Unit test FUNCTION `FUN_SP_Deg2Rad` | Sez. 1 — 4 casi |
| UT-F04 | Unit test FUNCTION `FUN_SP_Rad2Deg` | Sez. 1 — 4 casi |
| UT-F05 | Unit test FUNCTION `FUN_SP_Atan2` | Sez. 1 — 8 casi |
| UT-F06 | Unit test FUNCTION `FUN_SP_NormAng` | Sez. 1 — 7 casi |
| UT-F07 | Unit test FUNCTION `FUN_SP_AngDiff` | Sez. 1 — 5 casi |
| UT-F08 | Unit test FUNCTION `FUN_SP_Dist2D` | Sez. 1 — 5 casi |
| UT-F09 | Unit test FUNCTION `FUN_SP_Lerp` | Sez. 1 — 5 casi |
| UT-F10 | Unit test FUNCTION `FUN_SP_DigCh` | Sez. 1 — 4 casi |
| UT-F11 | Unit test FUNCTION `FUN_SP_DigVal` | Sez. 1 — 4 casi |
| UT-F12 | Unit test FUNCTION `FUN_SP_TokN` | Sez. 1 — 7 casi |
| UT-F13 | Unit test FUNCTION `FUN_SP_TokCnt` | Sez. 1 — 5 casi |
| UT-F14 | Unit test FUNCTION `FUN_SP_Trims` | Sez. 1 — 5 casi |
| UT-F15 | Unit test FUNCTION `FUN_SP_StrToLReal` | Sez. 1 — 8 casi |
| UT-F16 | Unit test FUNCTION `FUN_SP_StrToUi` | Sez. 1 — 5 casi |
| UT-F17 | Unit test FUNCTION `FUN_SP_StrToUd` | Sez. 1 — 4 casi |
| UT-F18 | Unit test FUNCTION `FUN_SP_UiToStr` | Sez. 1 — 3 casi |
| UT-F19 | Unit test FUNCTION `FUN_SP_UdToStr` | Sez. 1 — 3 casi |
| UT-F20 | Unit test FUNCTION `FUN_SP_LRealToStr` | Sez. 1 — 6 casi |
| UT-F21 | Unit test FUNCTION `FUN_SP_VisAppend` | Sez. 1 — 4 casi |
| UT-F22 | Unit test FUNCTION `FUN_SP_StrSum` | Sez. 1 — 5 casi |
| UT-F23 | Unit test FUNCTION `FUN_SP_ByteCh` | Sez. 1 — 5 casi |
| UT-F24 | Unit test FUNCTION `FUN_SP_RtcToStr` | Sez. 1 — 4 casi |
| UT-F25 | Unit test FUNCTION `FUN_SP_TickToRtc` | Sez. 1 — 5 casi |
| UT-F26 | Unit test FUNCTION `FUN_SP_ErrorText` | Sez. 1 — 5 casi |
| UT-F27 | Unit test FUNCTION `FUN_SP_SrcText` | Sez. 1 — 4 casi |
| UT-F28 | Unit test FUNCTION `FUN_SP_TrfX` | Sez. 1 — 4 casi |
| UT-F29 | Unit test FUNCTION `FUN_SP_TrfY` | Sez. 1 — 4 casi |
| UT-F30 | Unit test FUNCTION `FUN_SP_InvTrfX` | Sez. 1 — 4 casi |
| UT-F31 | Unit test FUNCTION `FUN_SP_InvTrfY` | Sez. 1 — 3 casi |
| UT-F32 | Unit test FUNCTION `FUN_SP_TrfTh` | Sez. 1 — 3 casi |
| UT-F33 | Unit test FUNCTION `FUN_SP_InvTrfTh` | Sez. 1 — 2 casi |
| UT-F34 | Unit test FUNCTION `FUN_SP_RotX` | Sez. 1 — 4 casi |
| UT-F35 | Unit test FUNCTION `FUN_SP_RotY` | Sez. 1 — 3 casi |
| UT-F36 | Unit test FUNCTION `FUN_SP_Pose3InWin` | Sez. 1 — 4 casi |
| UT-F37 | Unit test FUNCTION `FUN_SP_FitYaw` | Sez. 1 — 4 casi |
| UT-F38 | Unit test FUNCTION `FUN_SP_ClusterResidual` | Sez. 1 — 4 casi |
| UT-F39 | Unit test FUNCTION `FUN_SP_CamPreset` | Sez. 1 — 8 casi |
| UT-F40 | Unit test FUNCTION `FUN_SP_RobCfgDefault` | Sez. 1 — 8 casi |
| UT-D01…UT-D81 | Unit test TYPE/DUT | Sez. 2 |
| UT-G01…UT-G10 | Unit test GVL | Sez. 2 |
| FB-T01 | FB `SP_AlarmMgr` in isolamento | Sez. 3 |
| FB-T02 | FB `SP_Logger` in isolamento | Sez. 3 |
| FB-T03 | FB `SP_MovAvg` in isolamento | Sez. 3 |
| FB-T04 | FB `SP_Calib2D` in isolamento | Sez. 3 |
| FB-T05 | FB `SP_ConvDrive` in isolamento | Sez. 3 |
| FB-T06 | FB `SP_ConvEncoder` in isolamento | Sez. 3 |
| FB-T07 | FB `SP_Conveyor` in isolamento | Sez. 3 |
| FB-T08 | FB `SP_DrvAscii` in isolamento | Sez. 3 |
| FB-T09 | FB `SP_DrvCognex` in isolamento | Sez. 3 |
| FB-T10 | FB `SP_DrvGeneric` in isolamento | Sez. 3 |
| FB-T11 | FB `SP_DrvKeyence` in isolamento | Sez. 3 |
| FB-T12 | FB `SP_Socket` in isolamento | Sez. 3 |
| FB-T13 | FB `SP_VisionCam` in isolamento | Sez. 3 |
| FB-T14 | FB `SP_ItemQueue` in isolamento | Sez. 3 |
| FB-T15 | FB `SP_TrkFeed` in isolamento | Sez. 3 |
| FB-T16 | FB `SP_BatchMgr` in isolamento | Sez. 3 |
| FB-T17 | FB `SP_PatternGen` in isolamento | Sez. 3 |
| FB-T18 | FB `SP_LoadBalancer` in isolamento | Sez. 3 |
| FB-T19 | FB `SP_ZoneGuard` in isolamento | Sez. 3 |
| FB-T20 | FB `SP_RobMotion` in isolamento | Sez. 3 |
| FB-T21 | FB `SP_Robot` in isolamento | Sez. 3 |
| FB-T22 | FB `SP_ToolCtl` in isolamento | Sez. 3 |
| FB-T23 | FB `SP_Dispatch` in isolamento | Sez. 3 |
| FB-T24 | FB `SP_Stats` in isolamento | Sez. 3 |
| FB-T25 | FB `SP_System` in isolamento | Sez. 3 |
| FB-T26 | FB `SP_FileIo` in isolamento | Sez. 3 |
| FB-T27 | FB `SP_RecipeMgr` in isolamento | Sez. 3 |
| FB-T28 | FB `SP_RetainMgr` in isolamento | Sez. 3 |
| FB-T29 | FB `SP_SimCamera` in isolamento | Sez. 3 |
| FB-T30 | FB `SP_SimConveyor` in isolamento | Sez. 3 |
| FB-T31 | FB `SP_GripPlanner` in isolamento | Sez. 3 |
| FB-T32 | FB `SP_Collision` in isolamento | Sez. 3 |
| FB-T33 | FB `SP_Maint` in isolamento | Sez. 3 |
| FB-T34 | FB `SP_Oee` in isolamento | Sez. 3 |
| FB-T35 | FB `SP_SelfTest` in isolamento | Sez. 3 |
| M-* | Matrice METHOD (209 voci) | Sez. 4 |
| PRG-T01…PRG-T10 | Program e task ciclici | Sez. 5 |
| INT-1…INT-8 | Integrazione CFG 1..8 | Sez. 6 |
| FT-01…FT-25 | Fault injection e stress | Sez. 7 |
| BM-01…BM-14 | Benchmark Prima vs Dopo | Sez. 8 |
| HW-01…HW-10 | Collaudo macchina reale | Sez. 9 |
| SET-01…SET-12 | Preparazione ambiente | Sez. 0 |
| SQ-01…SQ-25 | Sequenze Watch rapide | App. F |


## Appendice H — Regole di progetto da verificare a ogni modifica (gate di conformita)

Checklist rapida da rieseguire dopo OGNI modifica al codice, prima di rilanciare i test:

| # | Regola | Come si verifica |
|---|---|---|
| 1 | Nessun puntatore/referenza/`ADR()` | Ricerca `ADR(` nei 73 fogli: 0 occorrenze. |
| 2 | Nessuna `ACTION` | Ricerca `ACTION`: 0 occorrenze. |
| 3 | Nessun array di FB | Verifica dichiarazioni array: solo DUT/TYPE base. |
| 4 | Nessun `VAR_IN_OUT` usato dentro i METHOD | Ricerca nei body METHOD: solo VAR/VAR_IN. |
| 5 | Nessuna ricorsione | Analisi chiamate: nessuna funzione/metodo che richiama se stesso. |
| 6 | `THIS.METHOD` nelle chiamate interne al parent FB | Ricerca chiamate dirette senza prefisso. |
| 7 | `VAR_IN_OUT` mai lasciati non assegnati | Per ogni chiamata con parametri inout: assegnazione esplicita del valore di uscita. |
| 8 | Costanti solo nel foglio dati di dichiarazione (o GVL) | Verifica usi incrociati. |
| 9 | Solo funzioni supportate da iCube Engineer 2026.6 | Confronto con l elenco di Sez. 0.2/SET-03. |
| 10 | Commenti in inglese con intestazioni | Ispezione header di ogni FUNCTION/FB/METHOD. |
| 11 | Score/pesi in `LREAL` con cast `LREAL_TO_REAL` verso API REAL | Ricerca cast mancanti. |
| 12 | Array letterali con bounds espliciti `ARRAY[1..N]` | Ispezione dichiarazioni. |


---

*Fine del manuale — generato il 2026-10-13 — SmartPick_iC v1.8.0 — copertura: 40 FUNCTION, 35 FB, 209 METHOD, 4 PROGRAM, 81 TYPE, 73 fogli ST.*
