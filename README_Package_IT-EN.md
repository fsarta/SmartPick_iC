# SmartPick_iC - Vision-Guided High-Speed Picking Suite
# Guida rapida al pacchetto / Package quick guide (IT-EN)

Target: Yaskawa iC 9226M-EC - iCube Engineer - IEC 61131-3 Structured Text
Scala: 4 robot - 8 convogli/feed - 2 camere - 4 tool/robot - 32 tipi prodotto
Release: v1.8.0 (orologio reale NATIVO Yaskawa: Y_YA_RealTimeClock + Yt_YA_RTC_Struct, tipo IEC DT ELIMINATO ovunque, tick monotono per le durate / native Yaskawa RTC binding, IEC DT type REMOVED everywhere, monotonic tick for durations; TUTTI i metodi e function hanno un tipo di ritorno / ALL methods and functions carry a return type; convenzione unità: rotazioni in GRADI e distanze in mm / units convention: ALL rotations in DEGREES and distances in mm; architettura MULTI-TASK 3 task ciclici 2/10/100 ms; config TUTTA in testo strutturato)

## Struttura / Structure

    SmartPick_iC/
    |- 00_ImportOrder.st              Ordine di importazione dei fogli in iCube / worksheet import order
    |- 00_TaskConfig_IT-EN.md         Configurazione task iCube: 3 task ciclici + contratto concorrenza / iCube task configuration: 3 cyclic tasks + concurrency contract
    |- 01_Common/                     Enum, struct, costanti, parser, logger, allarmi, formattatori RTC / enums, consts, parser, logger, alarms, RTC formatters
    |- 02_Geometry/                   Trasformazioni 2D + calibrazione SP_Calib2D / 2D transforms + calibration
    |- 03_Conveyor/                   Encoder, drive, arbitraggio slow-stop / encoders, drives, slow/stop arbitration
    |- 04_Vision/                     Socket TCP, protocol engine, driver Cognex/Keyence/Generic, preset / drivers + presets
    |- 05_Tracking/                   Coda anellare pezzi + tracking feed + ReserveCluster / item queue + feed + cluster reservation
    |- 06_Pattern/                    Pattern vassoi multi-livello + batch / multi-layer trays + batches
    |- 07_LoadSharing/                4 strategie di distribuzione + ZoneGuard / load sharing + zone interlock
    |- 08_Robot/                      FSM pick-place (inclusa discesa sincronizzata GripEval), motion adapter, tool / FSM incl. sync cluster descent
    |- 09_Production/                 System, Dispatch (flusso cluster), Stats / orchestration, job building, KPI
    |- 10_Persistence/                Retain, file I/O, ricette CSV / retain, file I/O, CSV recipes
    |- 11_Simulation/                 Convogli e camere virtuali / virtual conveyors and cameras
    |- 12_Application/               GVL + 3 programmi task (TaskFast/TaskMain/TaskSvc) + PRG_SP_ConfigInit (8 configurazioni ST) + CONFIG_EXAMPLES / GVLs + 3 task programs + 8 ST example configurations + doc
    |- 13_MultiGrip/                  Planner cluster multi-grip avanzato (R-07) / advanced multi-grip cluster planner
    |- 14_Collision/                  Crash prevention avanzata: zone + velocita' + separazione TCP (R-05b) / advanced crash prevention
    |- 15_Professional/               OEE/MTBF/MTTR, manutenzione predittiva, self-test (R-16) / OEE, maintenance, self-test
    |- Recipes/                       Formato backup CSV opzionale + validatore / optional CSV backup format + validator
    |- Firmware/                      FW-1 CHIUSO IN CODICE: MC_TrackConveyorBelt integrato + procedura on-site / FW-1 closed in code: MC_TrackConveyorBelt integrated + on-site procedure
    |- Hardware/                      Mappa I/O di impianto (HW-3) / plant I/O map template
    |- guide_assets/                  Sorgenti grafica guida / guide artwork sources
    |- SmartPick_iC_ArchitectureGuide.pdf   Guida completa 20 pagine IT-EN (TOC, architettura, integrazione, test, cap. 12 v1.2)

## Novita' v1.9 / What is new in v1.9

- CONFORMITA' RIGOROSA iCube Engineer 2026.6 & REVISIONE TOTALE:
  - Rimosso il file obsoleto `01_Common/FUN_SP_DtToStr.st` (usava il tipo `DT`).
  - Rimosso ogni uso di `ADR()` da `04_Vision/FB_SP_Socket.st` e `10_Persistence/FB_SP_FileIo.st`.
  - Spostata la lettura posa gruppo in `08_Robot/FB_SP_RobMotion.st` nel body del FB per evitare qualsiasi accesso a `VAR_IN_OUT ioGrp` dentro `METHOD`.
  - Sostituiti tutti i limiti `ARRAY[1..GC_*]` con letterali interi e rimosse tutte le `VAR CONSTANT` locali ai FB (`FB_SP_Calib2D`, `FB_SP_Stats`); rimossa la struct `GC_stRtcNil` da `VAR CONSTANT` in `GVL_SP_Const.st`.
  - Incapsulamento rigoroso di tutti i FB (`VAR_INPUT` / `VAR_OUTPUT` / wrapper methods in `SP_System`, `SP_Dispatch`, `SP_Robot`, `SP_Collision`, `SP_VisionCam`, `SP_Logger`, `SP_AlarmMgr`, `SP_SimCamera`).
  - Corretti tutti i cast `<SRC>_TO_<DST>`, tipi `REAL`/`LREAL` (`rScore`, `rWeight`, `rMinScore`, `rMaxWeight`), indici `MID`/`LEFT` (`INT`) e `FOR` loop bounds in tutti i 73 fogli `.st`.
  - Risolti i bug logici e di runtime: `FUN_SP_RtcToStr` (clamp mese 1..12 e spazio separatore), `SP_ConvEncoder` (`rEncScale`), `SP_Conveyor` (`stOut.rReqFactor`), `SP_VisionCam` (`tInterval`, `TriggerNow`, `Configure` driver), `SP_DrvAscii` / `SP_SimCamera` (reset code circolari e `FUN_SP_UdToStr`), `SP_ItemQueue` (proiezione pick-line con `rBeltCap`), `SP_TrkFeed` (`rZWorld := stCfg.rZBelt`), `SP_PatternGen` (reset `m_bInit`/contatori, avanzamento strato in `BatchStart`, `udiGen`, slot target in `NotifyPlaced`, fronte di salita sensori vassoio), `SP_LoadBalancer` (`Unmatched`), `SP_ZoneGuard` (`m_aiHeldZone`), `SP_Robot` (segno `CupPose`, `bPicked := TRUE` in `GripEval`), `SP_Dispatch` (evitato deadlock stato 5, `uiCount` cluster, wrap tool mask), `SP_System` (`SetBatch`, `Stats()` ciclico, `bResilience`, `bAutoRestart`, `bStopConvsOnPause`, `bClearItemsPulse`), `SP_RecipeMgr` (allineamento enum, `iDir`, `iPriority` con segno, `sInName`), `SP_GripPlanner` (ancora e output dopo pruning), `PRG_SP_ConfigInit` (`ET_SP_CamDrv`), `PRG_SP_TaskFast` (direzione `sim1..8`, `simCam1/2` round-robin su tutti i nastri attivi, `bReleasePend` per robot).

## Novita' v1.8 / What is new in v1.8

- OROLOGIO REALE NATIVO Yaskawa (richiesta cliente: il tipo IEC "DT" non è
  offerto dall'editor dichiarazioni di iCube su questo target): nuovo GVL
  12_Application/GVL_SP_Rtc.st con il FB ufficiale Y_YA_RealTimeClock
  (libreria Y_Yaskawa_Toolbox) e la struct Yt_YA_RTC_Struct
  (Year/Month/Day/Hour/Minute/Second/mSec, INT). Il wall clock alimenta
  timestamp di log, allarmi, self-test e display HMI; in simulazione o su
  errore RTC interviene il fallback deterministico FUN_SP_TickToRtc.
  Le DURATE (timeout socket, timeout risposta camera, trigger intervallo)
  passano al TICK MONOTONO g_udiTickMs [ms] avanzato dal task veloce:
  mai influenzato da salti di orologio (NTP/DST), wrap-safe con sottrazione
  unsigned. Sostituzioni: FUN_SP_DtToStr -> FUN_SP_RtcToStr ('YYYY-MM-DD
  HH:MM:SS.mmm') + FUN_SP_TickToRtc; campi struct dtTime/dtRaised/dtCleared/
  dtRun -> stTime/stRaised/stCleared/stRun; sentinella GC_stRtcNil;
  input FB dtNow -> stNow (Svc) / udiTickMs (Fast); vecchi CONFIRM "read
  clock controllore" CHIUSI. / NATIVE Yaskawa real-time clock (customer
  request: the IEC "DT" type is not offered by the iCube declaration
  editor on this target): new GVL_SP_Rtc with the official
  Y_YA_RealTimeClock FB (Y_Yaskawa_Toolbox) + Yt_YA_RTC_Struct; wall clock
  feeds log/alarm/self-test/HMI timestamps, deterministic tick fallback
  in simulation or on RTC failure; DURATIONS (socket/camera timeouts,
  interval trigger) move to the monotonic millisecond tick g_udiTickMs
  advanced by the fast task (immune to wall-clock jumps, wrap-safe).
  FUN_SP_RtcToStr + FUN_SP_TickToRtc replace the DT formatter; struct
  fields renamed; GC_stRtcNil sentinel; CONFIRM closed.
- TIPO DI RITORDO SU TUTTI I METODI E FUNCTION (richiesta cliente):
  ogni METHOD ora dichiara un ritorno SIGNIFICATIVO - esito (BOOL),
  conteggio (UINT/UDINT/SINT, es. AckAll, Logger.Clear, ClearItems,
  HarvestFromDrv, SpawnBatch, CountActive, ItemQueue.ClearAll) o ack di
  esecuzione per le procedure interne (Step/Publish/Fsm/...). Il ritorno
  resta facoltativo da usare sul call-site; il nuovo linter
  scripts/sp_ret_test.py verifica che non esista alcun metodo void e che
  ogni metodo assegni il proprio ritorno (198 metodi tipizzati).
  / RETURN TYPE ON ALL METHODS AND FUNCTIONS: every METHOD now declares a
  meaningful return - outcome (BOOL), count (UINT/UDINT/SINT) or an
  execution ack for internal procedures; using the return at the call
  site stays optional; new linter sp_ret_test.py enforces zero void
  methods and return assignment (198 typed methods).

## Novita' v1.7 / What is new in v1.7

- CONVENZIONE UNITÀ (richiesta cliente): **tutte le rotazioni in GRADI** e
  **tutte le distanze in mm** in ogni variabile, costante, configurazione,
  ricetta, HMI e simulazione. Le funzioni trigonometriche IEC (SIN/COS/ATAN,
  radianti per standard) ricevono la conversione esplicita `GC_DEG2RAD` al
  punto di chiamata; `FUN_SP_Atan2` e `FUN_SP_NormAng` lavorano in gradi
  ((-180, 180]); nuove costanti `GC_90/GC_180/GC_360`; `GC_ANG_EPS` ora
  0.03 deg. Il flag camera si chiama ora `bThInRad` (FALSE = la camera
  invia gradi, TRUE = radianti e vengono convertiti). Il formato backup
  CSV passa a **Recipe v2** (angoli in gradi): i file v1 (radianti) sono
  RIGETTATI all'import per evitare rotazioni ridimensionate in silenzio.
  La convenzione allinea anche l'interfaccia `MC_TrackConveyorBelt`
  (componente Theta in gradi, convenzione orientamento Yaskawa - da
  confermare in commissioning). / UNITS CONVENTION (customer request):
  **ALL rotations in DEGREES**, **ALL distances in mm** across variables,
  constants, configs, recipes, HMI and simulation; IEC trig functions get
  an explicit `GC_DEG2RAD` conversion at the call site; `FUN_SP_Atan2` and
  `FUN_SP_NormAng` work in degrees ((-180, 180]); new `GC_90/GC_180/GC_360`
  constants; `GC_ANG_EPS` now 0.03 deg; camera flag renamed to `bThInRad`
  (FALSE = camera sends degrees, TRUE = radians converted on parse); CSV
  backup format bumped to **Recipe v2** (degrees), legacy v1 files are
  REJECTED on import; the convention also aligns the `MC_TrackConveyorBelt`
  Theta component with the Yaskawa orientation degree unit (confirm on
  commissioning).

## Novita' v1.6 / What is new in v1.6

- Architettura MULTI-TASK (3 task ciclici con temporizzazioni diverse):
  PRG_SP_Main e' stato partizionato in PRG_SP_TaskFast (2 ms, motion-critico:
  encoder, tracking MC_TrackConveyorBelt, robot, camere, pattern, side-effect
  dispatcher - NESSUN file I/O ne' string building nel task veloce),
  PRG_SP_TaskMain (10 ms: SP_System, SP_Dispatch.Run, batch, statistiche) e
  PRG_SP_TaskSvc (100 ms: OEE, manutenzione, self-test, file/log/ricette/HMI).
  Comunicazione inter-task SOLO a scrittore unico + mailbox latched
  (GVL_SP_Sync: bCfgPend, stPattCmd, ring statistiche a cursori, snapshot
  contatori, richiesta log); FB_SP_Dispatch v1.6: richieste LATCHED (nessuna
  pulse persa per ordine di scansione, nessuna doppia esecuzione).
  Guida completa: 00_TaskConfig_IT-EN.md (creazione task in iCube, priorita',
  watchdog, budget CPU, regole di modifica, compatibilita' single-task).
  Beneficio: latenza encoder->target deterministica (le scritture su flash e
  i mirror HMI non stallano piu' il tracking), carico Fast tipicamente <20%.
  / MULTI-TASK architecture (3 cyclic tasks, different periods): the old
  single wiring program is split into TaskFast (2 ms motion-critical loop -
  NO file I/O, NO string building), TaskMain (10 ms orchestration) and
  TaskSvc (100 ms services). Cross-task communication is single-writer only
  + latched mailboxes (GVL_SP_Sync); SP_Dispatch v1.6 uses latched requests
  (never lost by scan order, never executed twice). Full guide:
  00_TaskConfig_IT-EN.md. Benefit: deterministic encoder->target latency,
  Fast task typically below 20% load.
- Fix: la variabile stJI era usata ma non dichiarata in PRG_SP_Main v1.5
  (primo compile rigido); ora dichiarata in PRG_SP_TaskFast. / v1.5 used
  stJI without declaring it; now declared in PRG_SP_TaskFast.
- Nuovo test scripts/sp_task_test.py: linter statico del partizionamento
  (istanze mono-task, mailboxes single-writer, vietato file I/O nel Fast).
  / New static partitioning linter sp_task_test.py.

## Novita' v1.5 / What is new in v1.5

- Configurazione INTERAMENTE in testo strutturato: il nuovo POU
  12_Application/PRG_SP_ConfigInit.st scrive direttamente i mirror di
  configurazione (convogli, feed, telecamere, calibrazioni, pattern,
  batch, load sharing, zone, flag guardie) e pilota bApplyConfig per la
  ri-configurazione dei FB; OTTO configurazioni d'esempio (4 standard +
  4 miste/strane: un robot per tutti i nastri, nastri inversi con slot
  ruotati e 2 livelli, una camera sola su 4 feed con regioni diverse,
  matrice di stress con zone + collisione avanzata e priorita'
  invertite). Auto-apply al boot (bAutoBoot/iBootCfg): la cella nasce
  configurata dal codice. I CSV NON sono piu' richiesti: restano solo
  come backup/restore runtime (esportazione HMI). Documentazione:
  12_Application/CONFIG_EXAMPLES_IT-EN.md. Test: scripts/sp_cfg_test.py
  1322 check (schema, integrita' referenziale, anchor di regressione sui
  dati delle ex-ricette).
  / ALL-STRUCTURED-TEXT configuration: the new PRG_SP_ConfigInit POU
  writes the configuration mirrors directly (conveyors, feeds, cameras,
  calibrations, patterns, batches, load sharing, zones, guard flags) and
  pulses bApplyConfig; EIGHT example configurations (4 standard + 4
  mixed/strange: single robot on all belts, reverse belts with rotated
  slots and 2 layers, single camera on 4 feeds with different regions,
  stress matrix with zones + advanced collision and inverted
  priorities). Boot auto-apply (bAutoBoot/iBootCfg): the cell boots
  configured from code. CSVs are NO LONGER required: they remain only as
  the runtime backup/restore format (HMI export). Doc:
  12_Application/CONFIG_EXAMPLES_IT-EN.md. Tests: scripts/sp_cfg_test.py
  1322 checks (schema, referential integrity, regression anchors).

## Novita' v1.4 / What is new in v1.4

- Posa TRACCIATA nativa (specchio della presa): anche il place può girare su
  MC_TrackConveyorBelt con una seconda sessione sull'asse encoder
  dell'uscita. Selettore per feed GVL_SP_Fw.g_abPlaceTrack[i] + prerequisito
  globale g_eTrkMode = 1; fallback statico automatico (mai errori) quando il
  feed non e' cablato; discesa (Place) e distacco (Retreat) tracciati;
  flag diagnostico g_astRobStat[iR].bTrkPlace; la posa sincronizzata
  multi-coppa resta statica per progetto.
  / NATIVE tracked place (pick-side mirror): the place can run on
  MC_TrackConveyorBelt with a second session on the outfeed encoder axis.
  Per-feed selector GVL_SP_Fw.g_abPlaceTrack[i] + global prerequisite
  g_eTrkMode = 1; automatic static fallback (never a fault); tracked
  Place/Retreat; diagnostics flag bTrkPlace; the synchronized cluster
  place stays static by design.
- File configurazioni d'esempio / example configuration file:
  Recipes/CONFIG_EXAMPLES_IT-EN.md (4 scenari pronti / ready scenarios:
  tutto statico, pick tracking + place statico, belt-to-belt completo,
  mista per singolo outfeed) + ricetta Recipes/Demo_Belt2Belt.csv
  (2 inf + 2 out, uscite tracciate, cam simulate, validabile offline).
- v1.4.1: nuovo POU ST 12_Application/PRG_SP_ExampleCfg.st - applica in
  puro testo strutturato le configurazioni 1-4 con un impulso (selettori
  tracking + nome ricetta + impulso caricamento); i CSV restano i DATI
  letti dal PLC a runtime (SP_RecipeMgr via SysFile), modificabili senza
  ricompilare. / new ST POU applies configurations 1-4 in pure structured
  text with one pulse (tracking switches + recipe name + load pulse); the
  CSVs remain the RUNTIME DATA read by the PLC (SP_RecipeMgr via SysFile),
  editable without recompiling.
- Test comportamentali estesi / extended behavioral tests: sp_trk_test.py
  57/57 (24 nuovi per la posa tracciata / new tracked-place checks).

## Novita' v1.3 / What is new in v1.3

- Tracking convoglio NATIVO (FW-1 chiuso in codice): integrazione completa di
  MC_TrackConveyorBelt (PLCopen Part 4 §6.6 + estensioni Yaskawa) in SP_RobMotion
  con sessione di tracking (Execute/Active, watchdog 2 s), mosse tracciate e stacco
  in PCS, chiusura con mossa MCS in Aborting, errori 201/202.
  Selettore run-time GVL_SP_Fw.g_eTrkMode (0 = fallback cut-off v1.x, 1 = nativo);
  fallback automatico per le feed non cablate; simulazione invariata.
  Restano solo 4 conferme on-site di spelling enum/struct (worksheet §2.4).
  / NATIVE conveyor tracking (FW-1 closed in code): full MC_TrackConveyorBelt
  integration with tracking session, PCS pick/depart moves, Aborting-based
  release, errors 201/202, run-time selector and per-feed automatic fallback;
  only 4 on-site enum/struct spelling confirmations remain.

## Novita' v1.2 / What is new in v1.2

- Multi-grip avanzato (R-07): formazione cluster geometrica con SP_GripPlanner +
  ReserveCluster, prelievo sincronizzato in una sola discesa, verifica vuoto per
  coppa con re-grip individuale, audit payload/baricentro, place sincronizzato con
  fallback asincrono. / Advanced multi-grip: geometric cluster formation, one
  synchronized pick descent, per-cup verification with individual re-grip,
  payload/CoG audit, synchronized place with async fallback.
- Crash prevention avanzata (R-05b): SP_Collision con acquisizione ordinata di 2
  zone per robot (no deadlock per costruzione), limiti di velocita' per zona,
  separazione dinamica TCP-TCP (rampa di rallentamento + stop con isteresi),
  priorita' di servizio, diagnostica di attesa/contesa, allarmi 30..33.
  Attivazione: g_stSysCfg.bColAdv := TRUE + mappa g_aiFeedZone.
  / Advanced crash prevention: ordered 2-zone acquisition (deadlock-free),
  zone speed limits, dynamic TCP separation, priorities, diagnostics, alarms.
- Livello professional (R-16): SP_Oee (OEE = Disponibilita' x Performance x
  Qualita', MTBF/MTTR), SP_Maint (cicli pinza, scatti camera, ore nastro/pompa con
  soglie e allarme 40), SP_SelfTest (7 controlli di consistenza configurazione,
  allarme 41). Mirror HMI in GVL_SP_Hmi (bRunSelfTest, bShiftReset, bMaintReset).
  / Professional layer: OEE engine, predictive maintenance counters, self-test suite.

## Avvio rapido in simulazione / Simulation quick start

1. Importare i fogli seguendo 00_ImportOrder.st (13_MultiGrip prima di 05_Tracking) /
   import worksheets in the given order (13_MultiGrip before 05_Tracking)
2. Creare i 3 task ciclici e assegnare i programmi (00_TaskConfig_IT-EN.md §2);
   modalita' compatibilita': tutti e 3 sullo stesso task / create the 3 cyclic
   tasks and assign the programs; single-task compatibility: all 3 on one task
3. Impostare g_bSim := TRUE (GVL_SP_Prod) / set simulation mode
4. La configurazione 1 (baseline) e' attiva di default al boot (PRG_SP_ConfigInit,
   bAutoBoot); per un'altra: iCfg 1..8 + impulso bApply / configuration 1 (baseline)
   is active by default at boot; for another one: iCfg 1..8 + bApply pulse
5. Avviare il sistema; i convogli/camere virtuali generano pezzi / start; virtual belts feed items
6. Opzionale: applicare la configurazione 8 per zone + collisione avanzata;
   bRunSelfTest per la diagnosi di configurazione / optional: apply configuration 8
   for zones + advanced guard; bRunSelfTest for config diagnostics

## Punti da confermare in impianto / On-site confirmations

Vedere OPEN_POINTS_IT-EN.md e capitolo 11 della guida: nomi FB di tracking del
firmware (FW-1, unica attivita' ingegneristica con informazione del vendor),
bit di stato gruppo in modalita' inject (FW-2), mappa I/O (HW-3), formati di
output dei job camera (HW-4), scaling encoder, IP/porte camere, calibrazione
SP_Calib2D per ogni camera, FB di override velocita' del motion library per lo
scaling live R-05b (CONFIRM nel body di SP_Robot).
/ See OPEN_POINTS and guide ch.11; includes the velocity-override FB CONFIRM
for the R-05b live speed scaling.

## Note sul codice / Code notes

- Ogni dichiarazione di variabile e' commentata in inglese (scanner dedicato) /
  every variable declaration carries an English comment (scanner-verified)
- Tutte le chiamate firmware sono marcate CONFIRM nei 5 adapter / all firmware
  calls are CONFIRM-marked inside the 5 adapter FBs
- Vincoli rispettati: no puntatori, no reference, no ACTION, no array di FB,
  no ricorsione, metodi con sole VAR/VAR_IN, chiamate via THIS, costanti in GVL
- QA: 73 file ST, bilanciamento blocchi verificato; test comportamentali Python
  per ZoneGuard (7 scenari), moduli v1.2 (27 scenari, scripts/sp_adv_test.py),
  tracking v1.3/v1.4 (57 scenari, scripts/sp_trk_test.py), configurazioni ST
  v1.5 (1322 check, scripts/sp_cfg_test.py), tasking v1.6 (linter
  partizionamento, scripts/sp_task_test.py 155 check), unità v1.7
  (scripts/sp_units_test.py), RTC v1.8 (scripts/sp_rtc_test.py 40 check) e
  ritorni v1.8 (scripts/sp_ret_test.py 36 check su 198 metodi) / 73 ST files,
  block balance verified; Python behavioral mirrors PASS
- Nota guida PDF: il PDF resta a livello di contenuto v1.2 (riferisce il
  cablaggio single-task storico); la referenza v1.6 per i task e'
  00_TaskConfig_IT-EN.md / the PDF guide remains v1.2-level; the v1.6 task
  reference is 00_TaskConfig_IT-EN.md
