# SmartPick_iC — Task Configuration / Configurazione Task (v1.6.0)

**IT** — Guida alla configurazione dei task in iCube Engineer per la build multi-task v1.6 (3 task ciclici con temporizzazioni diverse). Questa è la referenza operativa; i commenti nei sorgenti ST sono in inglese e usano gli stessi nomi qui sotto.
**EN** — Task configuration guide for iCube Engineer, multi-task build v1.6 (3 cyclic tasks with different periods). This is the operational reference; ST source comments are in English and use the same names.

---

## 1. Perché 3 task / Why 3 tasks

**IT** — Dalla v1.1 alla v1.5 l'intera applicazione girava in un solo programma (`PRG_SP_Main`) assegnato a un task unico a ~4 ms. Tutto condivideva lo stesso ciclo: il loop motion-critico (encoder → predizione tracking → target robot) e i servizi "lenti" (scrittura file su flash, export log, mirror HMI, KPI). Conseguenze misurabili:

1. **Jitter di latenza**: una `SysFileWrite` su flash può bloccare il task per decine di ms; durante quel tempo nessun target di tracking viene aggiornato e la finestra di presa (`rSyncDist`) perde precisione a velocità di nastro elevate.
2. **Budget CPU sprecato**: per stare dentro il ciclo veloce con i servizi inclusi, il periodo del task unico doveva essere più largo del necessario per il motion.
3. **Nessuna protezione di priorità**: HMI, log e ricette competevano col motion sullo stesso task.

**IT — Soluzione v1.6** (partizionamento in 3 task ciclici, modello standard IEC 61131-3):

| Task (iCube) | Periodo | Priorità | Watchdog | Programma | Contenuto |
|---|---|---|---|---|---|
| `SP_Fast_2ms` | 2 ms | più alta | 10 ms (≈5 cicli) | `PRG_SP_TaskFast` | Tick monotono `g_udiTickMs` (orologio per le DURATE), applicazione config layer-motion, nastri simulati, convogli (encoder MC_ReadActualPosition), feed tracking (Housekeeping/NearDist), guardie zone/collisione, robot (MC_TrackConveyorBelt, MC_MoveLinearAbsolute), mirror, camere + drain, camere simulate, motori pattern, **side-effect dispatcher** |
| `SP_Main_10ms` | 10 ms | media | 30 ms | `PRG_SP_TaskMain` | Applicazione config layer-logica (dispatcher/system), decodifica comandi batch → mailbox, `SP_Dispatch.Run`, orchestratore `SP_System` (start/stop/pause, resiliency, batch service), consumo ring statistiche, pubblicazione contatori |
| `SP_Svc_100ms` | 100 ms | bassa | 500 ms | `PRG_SP_TaskSvc` (+ `PRG_SP_ConfigInit` se usato) | **Orologio reale `Y_YA_RealTimeClock` (v1.8)**, OEE, manutenzione predittiva, self-test, diagnostica collisione + allarmi, ring logger, registro allarmi, retain, ricette CSV (backup opzionale), log dump, mirror HMI di servizio |

**EN** — Until v1.5 everything ran in one ~4 ms task: the motion-critical loop (encoder → tracking prediction → robot targets) shared the cycle with "slow" services (flash file writes, log export, HMI mirrors, KPI math). A `SysFileWrite` can stall the task for tens of ms, freezing tracking updates exactly when belt speed makes the sync window tight. v1.6 splits the application into 3 cyclic tasks (table above): the 2 ms task keeps the tracking/robot/conveyor/camera loop with **no file I/O and no string building**; the 10 ms task owns orchestration and dispatcher decisions; the 100 ms task owns everything that may block.

---

## 2. Creazione dei task in iCube Engineer / Task creation

**IT** — (iCube Engineer → progetto → *Task Configuration*; i nomi esatti dei campi possono variare con la versione dell'IDE — **CONFIRM on-site**, stessa prassi dei marker FW):

1. Creare 3 task **ciclici** (`Cyclic`): `SP_Fast_2ms`, `SP_Main_10ms`, `SP_Svc_100ms` con i periodi della tabella §1.
2. Impostare le priorità in ordine decrescente: Fast > Main > Svc (pre-emptive priority scheduling).
3. Watchdog consigliati: 5× il periodo (10 / 30 / 500 ms).
4. Assegnare i programmi: `PRG_SP_TaskFast` → `SP_Fast_2ms`, `PRG_SP_TaskMain` → `SP_Main_10ms`, `PRG_SP_TaskSvc` → `SP_Svc_100ms`. `PRG_SP_ConfigInit` su `SP_Svc_100ms` (o `SP_Main_10ms`): è un POU impulso, non chiamato da altri.
5. **Sincronizzare le costanti GVL con la config reale**: `GVL_SP_Prod.g_uiDtMs := UDINT#2` (periodo Fast), `GVL_SP_Sync.uiMainDtMs := UDINT#10`, `GVL_SP_Sync.uiSvcDtMs := UDINT#100`. Questi valori alimentano le integrazioni (convogli, feed, robot, OEE, manutenzione): devono combaciare con i periodi reali.
6. Compilare, scaricare, verificare nel *Task Monitor* il carico per task (§5).

**EN** — Create 3 cyclic tasks with the §1 periods, priorities Fast > Main > Svc, watchdogs ≈5× period, assign the programs, then keep the GVL period constants in sync with the real configuration (`g_uiDtMs`, `uiMainDtMs`, `uiSvcDtMs`). Field names in the Task Configuration editor may vary per IDE version — CONFIRM on site.

---

## 3. Contratto di concorrenza / Concurrency contract

**IT** — In ST puro non esistono semafori; l'interfaccia tra i task è costruita solo su **scrittore-unico** e **caselle postali latched** (`GVL_SP_Sync`, `GVL_SP_Inst`). Nessuna richiesta può perdersi per l'ordine di scansione e nessuna viene eseguita due volte:

| Meccanismo | Direzione | Scrittore | Consumatore | Note |
|---|---|---|---|---|
| `bCfgPend` | Main → Fast | `PRG_SP_TaskMain` (§1) | `PRG_SP_TaskFast` (§2, clear) | Ri-applica `Configure` a conv/feed/cam/rob/patt/zg/col nello stesso task che li cicla |
| `stPattCmd[1..2]` | Main → Fast | TaskMain (latch `bStart`/`bAbort` + snapshot def) | TaskFast (esegue `StartBatch`/`AbortBatch`, clear) | I batch manager restano nel Main; i motori pattern nel Fast |
| `stPattStat[1..2]` | Fast → Main | TaskFast (pubblica `pattN.stStat`) | TaskMain (`SyncProgress`) | Stato batch per HMI/registry |
| `astStatEv[1..64]` + cursori | Fast → Main | TaskFast (push eventi pick/place/cycle) | TaskMain (drain → `AddPick/AddPlace/AddCycle`) | Catori `UDINT` wrap-safe; ring pieno → drop conteggiato in `udiStatDrop` |
| `stTotPub` / `rPphPub` | Main → Svc | TaskMain (snapshot contatori) | TaskSvc (mirror HMI) | Dati grade-HMI: tear cosmetico tollerabile, mai usati per il controllo |
| `bLogPend` / `sLogMsg` | Main → Svc | TaskMain | TaskSvc (scrive nel ring logger, clear) | Il Main non può chiamare il logger di un altro task |
| Richieste dispatcher (`abReqPulse`/`abJobPulse`/`abCancelPulse`) | Main → Fast | `SP_Dispatch.Run()` (solo SET, latch) | TaskFast (esegue side-effect, SET risposta + clear) | Modifica v1.6 in `FB_SP_Dispatch`: richieste latched finché consumate |
| Risposte dispatcher (`astResRsp`/`astClRsp`/`abResDone`/`astJobRes`/`abJobResDone`) | Fast → Main | TaskFast | FSM di `SP_Dispatch.Run()` | Come in v1.5, ma tra task |
| Mirror "freschi" (`g_astRobStat`, `g_astFeedIo`, `g_hmiSysStat`, `g_astHmiRob/Feed/Cam/Col`) | Fast → tutti | **Solo** TaskFast | Main/Svc (lettura) | Il task lento non copia mai dati motion |
| Config (arrays `g_ast*Cfg`) | editor/ricette → tutti | HMI offline / `PRG_SP_ConfigInit` / `SP_RecipeMgr` | tutti | **Regola**: scrittura consentita solo a cella ferma (identico a v1.5) |
| Comandi HMI one-shot (`g_hmiCmd`, `bApplyConfig`, `bSaveRecipe`, …) | HMI → task | Pannello | un solo consumatore per campo (chi lo azzera) | Invariato rispetto a v1.5 |

**EN** — Plain ST has no semaphores; every cross-task interface is single-writer and latched (table above). Dispatcher requests are latched by `Run()` and consumed exactly once by the fast task (v1.6 change in `FB_SP_Dispatch`); statistics flow through a cursor ring; the slow task never copies live motion data.

---

## 4. Regole di modifica / Where to put new code

**IT** — Per mantenere il contratto:

1. **Tutto ciò che tocca assi, encoder, code di tracking, robot, camere, motori pattern** → `PRG_SP_TaskFast`. Nessuna `g_File`/`g_Recipy`/stringhe lunghe/fastidiose nel Fast: è vietato introdurre file I/O nel task a 2 ms.
2. **Decisioni, FSM applicative, bilanciamento, batch** → `PRG_SP_TaskMain`.
3. **KPI, log, file, HMI, diagnostica** → `PRG_SP_TaskSvc`.
4. Una FB istanza toccata da più di un task deve stare in `GVL_SP_Inst`; i dati scambiati tra task in `GVL_SP_Sync` (con la tabella §3 aggiornata).
5. Ogni campo GVL ha **uno** scrittore. Se servono due scrittori, introdurre una mailbox come sopra, non allargare le eccezioni.
6. Il test `scripts/sp_task_test.py` verifica staticamente queste regole (partizionamento istanze, mailboxes, vietato il file I/O nel Fast, mirror single-writer): eseguirlo dopo ogni modifica.

**EN** — Motion/IO/queues/robots/cameras/pattern → Fast. Decisions/FSM/balancing/batch → Main. KPI/log/files/HMI/diagnostics → Svc. Cross-task FB instances live in `GVL_SP_Inst`, cross-task data in `GVL_SP_Sync`; every field has exactly one writer; `scripts/sp_task_test.py` enforces the rules statically.

---

## 5. Verifica delle prestazioni / Performance verification

**IT** — In iCube Engineer (Task Monitor / diagnostica runtime):

- **Carico per task** (obiettivo: <40% di ciclo sul Fast, <60% su Main/Svc). Il Fast, senza file I/O, tipicamente scende sotto il 20% con 4 robot/8 nastri a 2 ms.
- **Jitter**: il Fast deve mostrare deviazione di ciclo minima (spike = prevenzione: qualcosa di lento è finito nel Fast — controllare §4.1).
- `GVL_SP_Sync.udiStatDrop` deve restare a 0 in produzione: se cresce, il Main non drenà abbastanza veloce (aumentare l'anello o verificare il periodo reale).
- Commissioning: verificare che la finestra di tracking (test 1..8 di `FW_PATCH_ConveyorTracking_IT-EN.md`) regga a velocità di nastro nominale — il guadagno atteso è nella riduzione del jitter di latenza encoder→target, non nella velocità teorica del motion kernel (che gira comunque nel firmware).

**EN** — Target loads: Fast <40% (typically <20% here), Main/Svc <60%. `udiStatDrop` must stay 0. The expected gain is a deterministic encoder→target latency (no stalls from flash/HMI), which tightens tracking accuracy at high belt speeds; the motion kernel timing itself is firmware-owned.

---

## 6. Modalità compatibilità single-task / Single-task compatibility

**IT** — I tre programmi sono **task-agnostic**: assegnandoli tutti e tre allo **stesso** task ciclico (es. 4 ms come in v1.5) il sistema funziona identico — le mailbox aggiungono solo una scansione di latenza. In quel caso impostare `g_uiDtMs`/`uiMainDtMs`/`uiSvcDtMs` tutti = periodo del task. Utile per il primo commissioning o per target con un solo task utente configurabile.
**EN** — Assigning all three programs to the SAME cyclic task keeps full semantics (one scan of mailbox latency); set the three period constants to that period. Useful for first commissioning or constrained targets.

---

## 7. Cosa è cambiato dalla v1.5 / Migration notes

**IT** — Mappa delle sezioni (i numeri di sezione nei commenti restano stabili):

| v1.5 (`PRG_SP_Main`) | v1.6 |
|---|---|
| §1 orologio, §3 nastri sim, §4 convogli, §5 feed, §5b collisioni, §6 robot, §7 mirror | `PRG_SP_TaskFast` (stessi numeri) |
| §8 camere, §9 camere sim, §10 motori pattern (parte ciclo/queue) | `PRG_SP_TaskFast` |
| §11 side-effect (Reserve/OfferJob/results/Release) + mirror HMI freschi | `PRG_SP_TaskFast` (richieste **latched**, statistiche via ring) |
| §2 config (parte dispatcher/system) | `PRG_SP_TaskMain` §1 (+ richiesta `bCfgPend` al Fast) |
| §10 decode aiPattStart/Abort + SyncProgress | `PRG_SP_TaskMain` §2 (mailbox) |
| §11 `SP_Dispatch.Run` | `PRG_SP_TaskMain` §3 |
| §12 `SP_System` + comandi HMI | `PRG_SP_TaskMain` §3b |
| §12b OEE/Maint/SelfTest/diagnostica | `PRG_SP_TaskSvc` §3-6 |
| §1 orologio reale Y_YA_RealTimeClock (v1.8, fallback tick) | `PRG_SP_TaskSvc` §1 |
| §13 file/log/alm/retain/ricette/log dump/ack + mirror HMI di servizio | `PRG_SP_TaskSvc` §7-10 |

**IT** — Bug fix incluso: `PRG_SP_Main` v1.5 usava `stJI` senza dichiararlo (punto rigido al primo compile): ora `stJI` è dichiarato in `PRG_SP_TaskFast`. `FB_SP_Dispatch` v1.6: richieste latched (§3) — se si torna a un task unico NON serve ritoccare nulla.
**EN** — Section map above; the v1.5 missing `stJI` declaration is fixed; `FB_SP_Dispatch` latched requests require no changes for single-task builds.

---

## 8. FAQ

**IT**
- *Le pulse del dispatcher si possono perdere tra task?* No: dal v1.6 sono latched (SET da `Run()`, CLEAR solo dall'esecutore insieme alla risposta).
- *Un evento statistico può andarsi a leggere mentre il Fast lo scrive?* No: i cursori `udiStatWr/udiStatRd` sono `UDINT` a scrittore unico; lo slot viene pubblicato prima di incrementare il cursore.
- *Perché gli snapshot OEE non sono double-buffered?* Perché sono dati grade-HMI (cosmetici); tutto ciò che serve al controllo usa mailboxes scalari/latched.
- *Posso mettere `PRG_SP_ConfigInit` nel Fast?* Sconsigliato (scrive le config): meglio Svc o Main, comunque a cella ferma.

**EN** — Dispatcher requests cannot be lost (latched). Statistics slots are published before the producer cursor is incremented (single-writer UDINT cursors). OEE snapshots are HMI-grade on purpose; all control-relevant exchanges use latched mailboxes. Keep `PRG_SP_ConfigInit` out of the Fast task.
