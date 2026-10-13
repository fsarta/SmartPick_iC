# SmartPick_iC — Chiusura Punti Aperti / Open Points Closure Matrix
**Release:** v1.2.0 (advanced pack) — 2026-10-04
**Target:** Yaskawa iC 9226M-EC — iCube Engineer

Questa matrice riporta lo stato finale di ogni punto aperto della v1.0,
con la consegna corrispondente e ciò che resta da confermare in campo.
/ This matrix reports the final state of every v1.0 open point, with the
corresponding deliverable and what still needs on-site confirmation.

---

## 0. Novità v1.2 / v1.2 additions (richiesta utente "multi grip avanzato + crash prevention")

| ID | Richiesta / Request | Stato / State | Consegna / Deliverable |
|----|---------------------|---------------|------------------------|
| R-07 | Gestione multi grip avanzata / Advanced multi-grip | ✅ **CHIUSO / CLOSED** | `13_MultiGrip/` (SP_GripPlanner, FUN_SP_ClusterMath) + `ReserveCluster` in 05_Tracking + `GripSync`/`FbkCup` in SP_ToolCtl + stato `GripEval` in SP_Robot + flusso cluster in SP_Dispatch |
| R-05b | Crash prevention avanzata / Advanced crash prevention | ✅ **CHIUSO / CLOSED** | `14_Collision/` (SP_Collision: 2 zone ordinate per robot, limiti velocità per zona, separazione dinamica TCP-TCP, priorità, diagnostica, allarmi 30..33) — attivazione `g_stSysCfg.bColAdv` |
| R-16 | Livello professional / Professional layer | ✅ **CHIUSO / CLOSED** | `15_Professional/` (SP_Oee: OEE/MTBF/MTTR; SP_Maint: manutenzione predittiva, allarme 40; SP_SelfTest: 7 controlli, allarme 41) + mirror HMI |

Dettagli operativi / Operational details:
- Multi-grip: cluster ammesso quando `eGripMode = Sync` E `uiMaxGrip > 1` E
  `rMatchTol > 0` (default del profilo: Sync, 2 pezzi, tolleranza 8 mm).
  Caduta di tazza ⇒ re-grip individuale della sola coppa fallita (budget
  `uiRetries` per coppa); place sincronizzato solo se la formazione bersaglio
  entra in tolleranza, altrimenti fallback sequenziale automatico.
  / Cluster admitted per robot by cfg rules; failed cup ⇒ individual re-grip
  with per-cup retry budget; synchronized place only when the target
  formation fits, else automatic sequential fallback.
- Collisioni: con `bColAdv = FALSE` resta attivo lo ZoneGuard v1.1 (zero
  cambi di comportamento); con `TRUE` il robot riceve `bZoneOk` (grant) e
  `rVelScale` (rampa 0.1..1.0) — lo scaling raggiunge il motion adapter ogni
  ciclo via `SP_Robot.rVelScale`; su iC9200 collegare il FB di override
  velocità del gruppo al punto CONFIRM nel body di SP_Robot.
  / With bColAdv = FALSE the v1.1 ZoneGuard applies unchanged; with TRUE the
  robot receives grant + velocity scale (CONFIRM the group override FB on
  target, marked in the SP_Robot body).
- QA v1.2: 66 file ST bilanciati; test comportamentali Python dei nuovi moduli
  27/27 PASS (`scripts/sp_adv_test.py`); ricette Demo_Sim/Demo_Line1 ancora PASS.
  / 66 ST files balanced; 27/27 behavioral mirror scenarios PASS; recipes PASS.

---

## 1. Stato complessivo / Overall status

| ID | Punto aperto / Open point | Stato / State | Consegna / Deliverable |
|----|---------------------------|---------------|------------------------|
| Ricette | Configurazione di layout iniziale | ✅ **CHIUSO / CLOSED** | v1.2: `Recipes/Demo_Sim.csv` + `Demo_Line1.csv`; **v1.5.0: configurazioni ST in `PRG_SP_ConfigInit`** (CSV solo backup, `Recipes/README_Recipe_IT-EN.md`) |
| FW-1 | FB firmware conveyor tracking | ✅ **CHIUSO IN CODICE / CLOSED IN CODE (v1.3)** | `MC_TrackConveyorBelt` integrato in `FB_SP_RobMotion` (selettore `GVL_SP_Fw.g_eTrkMode`); restano 4 conferme di spelling enum/struct — `Firmware/FW_PATCH_ConveyorTracking_IT-EN.md` §2.4 |
| FW-2 | Uscite Ready/referenced del gruppo | ✅ **CHIUSO / CLOSED** | `12_Application/GVL_SP_Fw.st` (iniezione stato, modalità 0/1) |
| HW-3 | Mappatura I/O fisica | ✅ **CHIUSO / CLOSED** (template) | `Hardware/HW_IO_Map_IT-EN.md` |
| HW-4 | Preset modelli camera | ✅ **CHIUSO / CLOSED** | `04_Vision/FUN_SP_CamPreset.st` + selettore `g_aiCamModel` (HMI) |
| R-05 | Anti-collisione tra robot (base) | ✅ **CHIUSO base / CLOSED (base)** | `07_LoadSharing/FB_SP_ZoneGuard.st` + config `g_aiFeedZone` / `bZoneGuard` |
| R-06 | Dati commissioning robot/tool | ✅ **CHIUSO / CLOSED** | `12_Application/FUN_SP_RobCfgDefault.st` (fix anche del primo avvio) |

**Aggiornamento v1.3:** il FB di tracking è stato identificato dall'utente
sulla documentazione ufficiale (`MC_TrackConveyorBelt`, help icubecontrol.com
+ release notes iCube Control 2025-6/2026-6) e **integrato nel codice** con
selettore run-time; la procedura on-site si è ridotta a 4 conferme di
spelling (§2.4 del worksheet).
/ **v1.3 update:** the tracking FB was identified by the user from the
official documentation (MC_TrackConveyorBelt) and **integrated in code**
with a run-time selector; the on-site procedure is now only 4 spelling
confirmations (worksheet §2.4).

---

## 2. Dettaglio delle consegne / Deliverable detail

### 2.1 Configurazioni d'esempio (v1.2: ricette CSV / v1.5.0: in ST)
Storicamente due ricette CSV complete (`Demo_Sim.csv`, `Demo_Line1.csv`)
nel formato `SP_RecipeMgr` (v1), validate con `SP_RecipeCheck.py`.
**v1.5.0: sostituite dalle otto configurazioni ST** di
`PRG_SP_ConfigInit` (stessi dati, vedi `12_Application/CONFIG_EXAMPLES_IT-EN.md`);
i CSV restano solo come formato di backup runtime.
/ Historically two complete CSV recipes (`Demo_Sim.csv`, `Demo_Line1.csv`)
in the exact `SP_RecipeMgr` (v1) format. **v1.5.0: replaced by the eight ST
configurations** of `PRG_SP_ConfigInit` (same data, see
`12_Application/CONFIG_EXAMPLES_IT-EN.md`); CSVs remain only as the runtime
backup format.

Nota tecnica / Technical note: durante la validazione è stato trovato e
corretto un bug del parser 32-bit (`FUN_SP_StrToUd` aggiunta in
`FUN_SP_Parse.st`, 4 punti import + 2 export in `SP_RecipeMgr`).
/ During validation a 32-bit parser bug was found and fixed
(`FUN_SP_StrToUd` added in `FUN_SP_Parse.st`; 4 import + 2 export sites in
`SP_RecipeMgr`).

### 2.2 FW-2 — stato gruppo (chiuso in codice)
- `GVL_SP_Fw.g_eFwStatMode`: 0 = proxy (default, simulazione e primavio),
  1 = iniezione bit reali.
  / 0 = proxy (default, simulation and first power-up), 1 = inject real bits.
- `g_abFwGrpReady[]` / `g_abFwGrpRef[]`: unici punti di cablaggio, già
  propagati Main → `SP_Robot` → `SP_RobMotion`.
  / Single wiring points, already propagated Main → `SP_Robot` → `SP_RobMotion`.
- Fail-safe: cablaggio errato ⇒ robot resta `Init`, mai movimento.
  / Fail-safe: wrong wiring ⇒ robot stays `Init`, never moves.

### 2.3 FW-1 — tracking (CHIUSO IN CODICE v1.3 / CLOSED IN CODE v1.3)
- `MC_TrackConveyorBelt` (PLCopen Part 4 §6.6 + estensioni Yaskawa) è
  integrato in `FB_SP_RobMotion`: sessione di tracking (Execute/Active,
  watchdog 2 s), mosse tracciate e stacco in **PCS**, chiusura con mossa
  MCS in `Aborting`, errori 201/202, mirror sessione in simulazione.
  / MC_TrackConveyorBelt integrated in FB_SP_RobMotion: tracking session
  (Execute/Active, 2 s watchdog), tracked pick and depart in PCS, session
  closed by the next MCS move in Aborting, errors 201/202, session mirror
  in simulation.
- Selettore run-time `GVL_SP_Fw.g_eTrkMode`: 0 = fallback cut-off v1.x
  (default, sempre disponibile), 1 = tracking nativo; fallback automatico
  per le feed con frame non cablato.
  / Run-time selector: 0 = v1.x cut-off fallback (default), 1 = native;
  per-feed automatic fallback when the frame is not wired.
- Geometria: `SP_Robot.SetBeltFrames` deriva i frame nastro dalle config
  feed (`rPhi = rRot + iDir·90°`); `CompBeltTargets` calcola la posa
  prodotto nel frame nastro alla cattura e i mirror PCS dei target;
  `MvToBelt` arma il bersaglio doppio mondo/PCS.
  / Geometry: SetBeltFrames derives belt frames from feed configs;
  CompBeltTargets computes the capture-fixed product pose in the belt
  frame and the PCS target mirrors; MvToBelt arms the dual target.
- Restano 4 conferme on-site di spelling enum/struct (§2.4 del worksheet):
  `MC_COORDSYS`, `MC_BUFFER_MODE`, `MC_ExecutionMode`, struct
  `TrackOptions` (stand-in `ST_SP_TrkOpt`).
  / 4 on-site spelling confirmations remain (worksheet §2.4).
- Piano di collaudo in 8 test (worksheet §2.5), inclusi pausa/resume a
  tracking attivo e feed in fallback.
  / 8-test commissioning plan (worksheet §2.5).

### 2.4 HW-3 — I/O (template pronto)
Tabelle complete: safety, 16+16 canali tool, 8 drive linea (analog/servo),
8 sensori vaschetta, 8 assi encoder, 4 gruppi cinematici, trigger camere,
config task (4 ms), checklist di messa in servizio in 9 passi.
/ Complete tables: safety, 16+16 tool channels, 8 line drives, 8 tray
sensors, 8 encoder axes, 4 kinematic groups, camera triggers, task config,
9-step commissioning checklist.

### 2.5 HW-4 — preset camere
`FUN_SP_CamPreset(stCfg, iModel)` applica i default di famiglia
(fill-if-empty, mai sovrascrive valori già commissionati); selettore HMI
`g_aiCamModel[x]` con −1=Cognex, 1=Keyence, 2=GenericTCP, 3=Simulated.
Composizione: preset modello → poi auto-preset protocollo del driver
(TRIG / R / token 1..5).
/ Family defaults, fill-if-empty; HMI selector; composes with the driver
protocol auto-presets.

### 2.6 R-05 — zona guard (base)
- `SP_ZoneGuard`: un robot per zona (latch fino a fine richiesta),
  priorità statica, passthrough trasparente quando disabilitato,
  no-deadlock per costruzione (una zona richiesta per robot).
  / One holder per zone (latched), static priority, transparent when
  disabled, deadlock-free by construction.
- Attivazione: `g_stSysCfg.bZoneGuard := TRUE` + mappa `g_aiFeedZone`
  (esempio della configurazione 8 di `PRG_SP_ConfigInit`; stesso esempio
  nei commenti di `PRG_SP_TaskFast`).
  / Enable via `bZoneGuard` + the `g_aiFeedZone` map.
- Il robot negato si congela come in pausa (prenotazioni conservate,
  riabilitazione automatica al grant).
  / Denied robot freezes like a pause (reservations kept, automatic
  release on grant).
- Test comportamentale Python (specchio del body): 7 scenari PASS
  (`scripts/sp_zoneguard_test.py`).
  / Python behavioral mirror: 7 scenarios PASS.
- Limiti documentati (R-05b): time-slicing, anti-collisione traiettoria.
  / Documented limits (R-05b): time-slicing, trajectory anti-collision.

### 2.7 R-06 — commissioning robot/tool (+ fix primo avvio)
- `FUN_SP_RobCfgDefault`: profilo generico sicuro (1 tool ventosa 2 coppie,
  2000/1200/1800 mm/s, Sync multi-grip 2, retry 1, offset Z +80/+40).
  / Safe generic profile (documented fields).
- **Bug rilevato e corretto / Bug found and fixed:** in v1.0
  `g_astRobCfg` non aveva mai inizializzazione ⇒ `robX.Configure()`
  restituiva `ErrParam` al primo avvio e i robot non uscivano mai da
  `Init`. Ora il one-shot di Main applica i default prima della
  Configure (idempotente: record già commissionato = invariato).
  / In v1.0 `g_astRobCfg` was never initialized ⇒ `Configure` failed at
  first boot. Main now applies defaults before Configure (idempotent).
- Feedback prese in simulazione: loopback automatico uscita PICK →
  ingresso FBK (Main, sezione 6) ⇒ `bVerifyPick` funziona offline.
  / Simulated pick feedback: PICK→FBK loop-back in Main ⇒ verification
  works offline.

---

## 3. Conferme residue in campo / Remaining on-site confirmations

| # | Attività / Activity | Dove / Where |
|---|---------------------|--------------|
| 1 | Nomi FB tracking reali + Variante A patch | `Firmware/FW_PATCH_ConveyorTracking_IT-EN.md` §2 |
| 2 | Cablaggio bit gruppo Ready/Ref + `g_eFwStatMode := 1` | idem §1 |
| 3 | Indirizzi %I/%Q reali sul coupler EtherCAT | `Hardware/HW_IO_Map_IT-EN.md` |
| 4 | IP/porta camere reali (o preset + modifica) | config 2 di `PRG_SP_ConfigInit` + `FUN_SP_CamPreset` |
| 5 | Calibrazione camera→feed (`SP_Calib2D`) per ogni camera | procedura guida, TC-07..TC-10 |
| 6 | Configurazione task reale: creare i 3 task ciclici (2/10/100 ms, priorità Fast>Main>Svc) e allineare `g_uiDtMs` / `uiMainDtMs` / `uiSvcDtMs` ai periodi reali (v1.6) | `00_TaskConfig_IT-EN.md` + task config iCube |
| 7 | **CHIUSO v1.8** — orologio controllore: non più un bind manuale nel task veloce; wall clock da `Y_YA_RealTimeClock` (TaskSvc sez. 1, fallback tick in sim/fault), durate dal tick monotono `g_udiTickMs` (TaskFast sez. 1) | `GVL_SP_Rtc` + `PRG_SP_TaskSvc` |
| 8 | **Unità orientamento interfaccia tracking (v1.7)**: con la convenzione gradi il 4° elemento di `ConveyorBeltOrigin`/`InitialObjectPosition` è passato in **gradi** (convenzione Yaskawa MCS); confermare su manuale/commissioning che la libreria si aspetta gradi e non radianti | `FB_SP_RobMotion` (nota CONFIRM in sezione 5) + `FW_PATCH` §2.4 |
| 9 | **Libreria Y_Yaskawa_Toolbox (v1.8)**: aggiungerla ai riferimenti progetto di iCube (Library manager) e confermare nome/revisione installata sul controllore; il FB `Y_YA_RealTimeClock` e il tipo `Yt_YA_RTC_Struct` devono risolversi a compile-time | `00_ImportOrder.st` (Library dependencies) + `GVL_SP_Rtc` |

---

## 4. Stato QA / QA status

| Check | Esito / Result |
|-------|----------------|
| QA strutturale ST (73 file: bilanciamento FB/FUN/METHOD/TYPE/VAR, segnaposto, ASCII, vincoli metodo) | **PASS** |
| Convenzione tipo di ritorno v1.8 (`scripts/sp_ret_test.py`): zero metodi/function void, ogni metodo assegna il proprio ritorno, 198 metodi tipizzati | **PASS** (36/36) |
| Linter partizionamento multi-task v1.6 (`scripts/sp_task_test.py`) | **PASS** (155/155) |
| Test comportamentale ZoneGuard (7 scenari) | **PASS** |
| Convenzione unità v1.7 (`scripts/sp_units_test.py`): zero residui radianti, conversione trig ai bordi, valori config in gradi, Recipe v2 | **PASS** (20/20) |
| Migrazione RTC v1.8 (`scripts/sp_rtc_test.py`): zero usi di DT, binding Y_YA_RealTimeClock, single-writer tick/orologio, aritmetica durate su tick | **PASS** (40/40) |
| Test tracking v1.7 (mirror Python in gradi, `scripts/sp_trk_test.py`) | **PASS** (57/57) |
| Test configurazioni ST (`scripts/sp_cfg_test.py`) | **PASS** (1322/1322) |
| Audit commenti variabili | **PASS** (1470/1470) |
| Vincoli progetto (no pointer/reference/ACTION/FB-array, metodi VAR+VAR_IN, `THIS.`, costanti in GVL) | **RISPETTATI / RESPECTED** |

Righe di codice ST: ~17.100 (73 file) + 5 documenti di integrazione.
/ ST code lines: ~17,100 (73 files) + 5 integration documents.
