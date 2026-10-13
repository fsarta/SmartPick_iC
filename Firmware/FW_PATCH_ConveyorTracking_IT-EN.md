# SmartPick_iC — FW Integration Worksheet / Scheda di Integrazione Firmware
**Chiusura punti aperti FW-1 (conveyor tracking) e FW-2 (stato gruppo)**
Target: Yaskawa iC 9226M-EC — iCube Engineer
Aggiornato: 2026-10-04 — **v1.4: + POSA TRACCIATA NATIVA (per outfeed)** — v1.3: FW-1 CHIUSO IN CODICE (MC_TrackConveyorBelt)

---

## 0. Stato / Status

| Punto | Stato / State | Risoluzione / Resolution |
|-------|--------------|--------------------------|
| **FW-1** — conveyor tracking | ✅ **CHIUSO IN CODICE / CLOSED IN CODE (v1.3 + v1.4)** | `MC_TrackConveyorBelt` (PLCopen Part 4 §6.6, confermato dalle release notes iCube Control 2025-6 / 2026-6) è integrato in `FB_SP_RobMotion` con selettore run-time `GVL_SP_Fw.g_eTrkMode`. **v1.4: anche la POSA può girare in tracking** su ogni uscita (`GVL_SP_Fw.g_abPlaceTrack[i]`, seconda sessione sull'asse encoder dell'uscita — §2.6). Restano **solo 4 conferme on-site sui nomi di enum/struct** (§2.4) — nessuna modifica strutturale. / `MC_TrackConveyorBelt` is integrated in `FB_SP_RobMotion` with the run-time selector `GVL_SP_Fw.g_eTrkMode`. **v1.4: the PLACE can run tracked as well** on each outfeed (`GVL_SP_Fw.g_abPlaceTrack[i]`, second session on the outfeed encoder axis — §2.6). Only **4 on-site spellings of enums/structs** remain to confirm (§2.4) — no structural change. |
| **FW-2** — nomi uscite Ready/referenced del gruppo | ✅ **CHIUSO in codice / CLOSED in code** | Iniezione stato tramite `GVL_SP_Fw` (`g_eFwStatMode`, `g_abFwGrpReady`, `g_abFwGrpRef`): passare a modalità 1 e cablare i bit reali in `PRG_SP_TaskFast` sezione 6 — nessuna modifica ai POI. / Status injection via `GVL_SP_Fw`: switch to mode 1 and wire the real bits in `PRG_SP_TaskFast` section 6 — no POU edits. |

> **Fonte / Source:** la documentazione pubblica di `MC_TrackConveyorBelt` è
> disponibile su icubecontrol.com (help online, voce *MC_TrackConveyorBelt*)
> e i dettagli implementativi Yaskawa sono confermati dalle release notes
> ufficiali (2025-6 e 2026-6): input `TrackOptions.SyncIn.ConveyorDistance`
> (> 0 obbligatorio da FW 2026.6, errore 9006), input `ExecutionMode`
> (`MC_ExecutionMode#Immediately/Delayed/Queued`), uscita di sync con il
> nastro, chiusura del tracking con mossa MCS in `Aborting`, asse encoder
> esterno come `ConveyorBelt`.
> / Public documentation of `MC_TrackConveyorBelt` is available in the
> icubecontrol.com online help; Yaskawa-specific behavior is confirmed by
> the official release notes (2025-6 / 2026-6): `TrackOptions.SyncIn.
> ConveyorDistance` (> 0 mandatory since FW 2026.6, error 9006),
> `ExecutionMode` (`Immediately/Delayed/Queued`), belt-sync output,
> tracking terminated by an MCS move in `Aborting`, external encoder axis
> as `ConveyorBelt`.

---

## 1. FW-2 — Stato gruppo Ready/referenced (procedura, 5 minuti / 5-minute procedure)

**Passo 1.** Individuare la sorgente dello stato del gruppo cinematico nella
vostra versione di libreria. In ordine di preferenza:
/ Find the kinematic group status source in your library version, in order
of preference:

1. `GroupEnable` → uscita `Done` / `Done` output (PLCopen Part 4);
2. un FB tipo `GroupReadStatus` / `GroupInfo` (uscita struct con bit
   `Ready` / `Referenced` / `Homed`);
3. i bit di stato direttamente sull'oggetto hardware `AXES_GROUP_REF`
   (espansi nel pannello I/O del dispositivo).

**Passo 2.** Nel body di `PRG_SP_TaskFast`, sezione 6, cablare:
/ In the `PRG_SP_TaskFast` body, section 6, wire:

```iecst
GVL_SP_Fw.g_abFwGrpReady[1] := <group 1 ready bit>;
GVL_SP_Fw.g_abFwGrpRef[1]   := <group 1 referenced bit>;
(* ... righe 2..4 analoghe / rows 2..4 alike ... *)
```

**Passo 3.** Impostare `GVL_SP_Fw.g_eFwStatMode := 1;` (HMI o init).
/ Set `GVL_SP_Fw.g_eFwStatMode := 1;` (HMI or init code).

**Verifica / Check:** in HMI, `g_astHmiRob[x].bOnline` deve passare a TRUE
solo quando il gruppo è realmente ready; in caso di errore di cablaggio il
robot resta in stato `Init` (comportamento fail-safe).
/ On the HMI, `g_astHmiRob[x].bOnline` must turn TRUE only when the group is
really ready; a wiring error keeps the robot in `Init` (fail-safe).

---

## 2. FW-1 — MC_TrackConveyorBelt: integrazione (già nel codice / already in code)

### 2.1 Come funziona / How it works

L'integrazione segue il modello PLCopen Part 4 §6.6 (Fig. 23 del manuale
PLCopen): il FB **non muove il gruppo**, attiva la trasformazione MCS↔PCS
che segue il nastro; le mosse comandate in PCS vengono quindi eseguite
sincronizzate con il prodotto.
/ The integration follows the PLCopen Part 4 §6.6 model: the FB does not
move the group, it activates the belt-following MCS↔PCS transformation;
moves commanded in PCS execute synchronized with the product.

```
                 ┌─────────────────────────────────────────────────┐
                 │                SP_RobMotion (body)              │
   pick request  │  TrackAbs edge ──> m_fbTrk (MC_TrackConveyorBelt)│
   (SP_Robot)    │        │             AxesGroup := ioGrp          │
                 │        │             ConveyorBelt := ioBelt      │
                 │        │             ConveyorBeltOrigin      ────┼── belt CS in MCS
                 │        │             InitialObjectPosition   ────┼── product at capture
                 │        │             ExecutionMode := Immediately│
                 │        │             TrackOptions.SyncIn.        │
                 │        │               ConveyorDistance > 0      │
                 │        ▼                                         │
                 │  wait Active ──> m_fbLin (MC_MoveLinearAbsolute) │
                 │                   CoordSystem := PCS  ───────────┼── tracked pick/depart
                 │  next static move (MCS, Aborting) ───────────────┼── ends the session
                 └─────────────────────────────────────────────────┘
```

Sequenza SmartPick (FSM `SP_Robot`, invariata nei nomi di stato):
/ SmartPick sequence (SP_Robot FSM, state names unchanged):

1. `MoveApp` — avvicinamento in **MCS** al punto di approccio previsto
   (cut-off prediction). Nessuna modifica rispetto a v1.x.
   / Approach in MCS to the predicted entry point (v1.x unchanged).
2. `TrackPick` — prima mossa `TrackAbs`: apre la sessione di tracking
   (Execute + Immediate), attende `Active` (watchdog 2 s, errore 202) e
   comanda la discesa in **PCS** sul punto prodotto (offset utensile
   ruotati nel frame nastro da `CompBeltTargets`).
   / First TrackAbs move: opens the session (Execute + Immediate), waits
   for Active (2 s watchdog, error 202), commands the descent in PCS to
   the product-fixed point (tool offsets rotated into the belt frame).
3. `Grip` — presa a prodotto fermo nel PCS (il nastro scorre sotto).
   / Grip while the product stands still in PCS (belt flows underneath).
4. `Depart` — stacco **ancora tracciato** (PCS): il robot segue il nastro
   durante il lift, come MotoPick 4.
   / Lift-off stays tracked (PCS): the robot follows the belt while
   lifting, MotoPick 4 style.
5. `MovePlace`/`Retreat` — prossima mossa statica **MCS** con
   `BufferMode := Aborting`: chiude la sessione (comportamento
   documentato Yaskawa), rilascio completato quando `Active` cala.
   / Next static MCS move with Aborting closes the session (documented
   Yaskawa behavior); release completes when Active drops.

**Pause/stop/fault:** la sessione viene rilasciata subito; alla ripresa il
prossimo `TrackAbs` riapre una sessione fresca con la posa prodotto nel
frame nastro (fissa alla cattura) — zero perdite, semantica MotoPick 4.
/ Pause/stop/fault release the session immediately; on resume the next
TrackAbs re-opens a fresh session with the capture-fixed belt-frame product
pose — zero loss, MotoPick 4 semantics preserved.

### 2.2 Dati che SmartPick passa al FB / Data wired into the FB

> **UNITS (v1.7.0):** distanze **[mm]**; la componente **θ (4° elemento) di
> `ConveyorBeltOrigin` e `InitialObjectPosition` è passata in GRADI**
> (convenzione orientamento Yaskawa MCS). Da confermare in §2.4 che la
> libreria si aspetta gradi; se il manuale indicasse radianti, aggiungere
> `* GC_DEG2RAD` sui soli 4° elementi in `SP_RobMotion` sezione 5.
> / **UNITS (v1.7.0):** distances **[mm]**; the **θ (4th element) of
> `ConveyorBeltOrigin` and `InitialObjectPosition` is passed in DEGREES**
> (Yaskawa MCS orientation convention). Confirm in §2.4 that the library
> expects degrees; if the manual states radians, add `* GC_DEG2RAD` on the
> 4th elements only in `SP_RobMotion` section 5.

| Parametro FW | Sorgente SmartPick | Dove si calcola |
|---|---|---|
| `AxesGroup` | `g_aGrp[robot]` | `PRG_SP_TaskFast` → `ioGrp` |
| `ConveyorBelt` (AXIS_REF) | `g_aAxisEnc[feed]` | `PRG_SP_TaskFast` → `ioaBelt` → `ioBelt` (per pick, via `m_iFeedNow`) |
| `ConveyorBeltOrigin` [X,Y,Z,θ] | origine feed nel mondo (`stWorld.rDx/.rDy` [mm]), `rZBelt` [mm], `rPhi = rRot + iDir·90°` [deg] | `SP_Robot.SetBeltFrames` + `CompBeltTargets` → `stBeltOrg` |
| `InitialObjectPosition` [X,Y,Z,θ] | posa prodotto nel frame nastro alla cattura: `x = iDir·rBeltCap` [mm], `y = −iDir·u` [mm], `z = rZWorld − rZBelt` [mm], `θ = yaw − rPhi` [deg] | `SP_Robot.CompBeltTargets` → `stObjBelt` |
| `TrackOptions.SyncIn.ConveyorDistance` | `rWinStart` della feed (guardia > 0, default 100 mm) | `SetBeltFrames` → `rSyncDist` |
| `ExecutionMode` | `MC_ExecutionMode#Immediately` (il gruppo è fermo quando la sessione apre) | `SP_RobMotion` body |
| Target PCS (pick/depart) | target mondo − base mondo, ruotati di −rPhi, ancorati alla posa prodotto nel nastro | `CompBeltTargets` → `m_stPtBelt` / `m_stDepBelt` → `stTargetBelt` |

### 2.3 Selettore run-time / Run-time selector

```iecst
GVL_SP_Fw.g_eTrkMode := 1;   (* 0 = fallback cut-off (v1.x), 1 = native tracked *)
```

- `0` (default): comportamento v1.x — posa prevista alla cut-off + mossa
  lineare MCS. Funziona senza opzione di tracking e in simulazione;
  tolleranza ≥ ±5 mm fino a ~0,3-0,5 m/s di nastro.
  / v1.x behavior — cut-off predicted pose + MCS linear move. Works
  without the tracking option and in simulation; ≥ ±5 mm up to ~0.3-0.5 m/s.
- `1`: tracking nativo. Richiede l'opzione attiva sul target (§2.1
  precondizioni) e le conferme §2.4. Il per-feed fallback resta automatico
  per le feed con `bUsed = FALSE` (frame non cablato).
  / Native tracking. Requires the option on the target and the §2.4
  confirmations; feeds with an unwired frame automatically stay fallback.

**Perché un selettore / Why a selector:** stesso build per simulazione,
collaudo e produzione; attivazione per linea dal pannello HMI/ricetta senza
toccare alcun POU; ritorno al fallback in un ciclo se qualcosa non torna in
collaudo. / One build for simulation, commissioning and production;
per-line enable from HMI/recipe; one-cycle rollback to fallback.

### 2.4 CONFERME on-site / On-site CONFIRMATIONS (4 voci, ~30 min)

I nomi seguenti dipendono dalla versione della libreria Yaskawa installata.
Verificarli in *Library Repository* e allineare le righe marcate `CONFIRM`
nel body di `FB_SP_RobMotion` (una riga ciascuna):
/ The following names depend on the installed Yaskawa library version.
Check them in the Library Repository and align the `CONFIRM`-marked lines
in the `FB_SP_RobMotion` body (one line each):

| # | Item | Dove / Where | Nota / Note |
|---|------|--------------|-------------|
| 1 | Enum sistema di coordinate: `MC_COORDSYS#PCS` / `#MCS` | chiamate `m_fbLin` (2 punti) | il nome alternativo tipico è `MC_CoordinateSystem#PCS` / typical alternative `MC_CoordinateSystem#PCS` |
| 2 | Enum buffer mode: `MC_BUFFER_MODE#Aborting` | chiamate `m_fbLin` + `m_fbTrk` | standard PLCopen, raro il divergere / PLCopen standard |
| 3 | Enum ExecutionMode: `MC_ExecutionMode#Immediately` | chiamata `m_fbTrk` | valori `Delayed`/`Queued` disponibili se si vuole armare durante l'avvicinamento / Delayed/Queued available to arm during the approach |
| 4 | Struct `TrackOptions` (stand-in `ST_SP_TrkOpt` in `DUT_SP_RobotTypes`) | dichiarazione `m_stTrkOpt` + chiamata `m_fbTrk` | sostituire il tipo locale con quello di libreria (membro usato: `SyncIn.ConveyorDistance`, LREAL, > 0) / replace the local stand-in with the library type |

Più la mappa uscite del FB (già allineata alla convenzione Yaskawa):
`Busy`, `Active` (trasformazione attiva), `CommandAborted`, `Error`,
`ErrorID`; l'uscita di sincronizzazione (`InSync`/`TrackState`) è esposta
come `bTrkInSync` quando la libreria la denomina `Active`-like — in caso di
uscita dedicata (es. `InSync`), aggiungerla alla chiamata `m_fbTrk` e
rifletterla in `bTrkInSync`.
/ Plus the FB output map (already aligned to the Yaskawa convention):
Busy, Active (transform running), CommandAborted, Error, ErrorID; if the
library exposes a dedicated sync output (e.g. InSync), add it to the
m_fbTrk call and mirror it in bTrkInSync.

### 2.5 Piano di collaudo / Commissioning test plan

| # | Test | Criterio / Criterion |
|---|------|----------------------|
| 1 | Dry-run (`bDryRun`) con nastro a 0.2 m/s, `g_eTrkMode = 1` | sessione apre (`bTrkSess`), `bTrkInSync` TRUE entro 2 s, nessun errore gruppo |
| 2 | Presa reale a 0.2 m/s | offset medio ≤ ±2 mm su 20 prese (meglio del fallback) |
| 3 | Velocità crescente 0.3 / 0.5 / 0.8 m/s | tolleranza stabile; il vantaggio nativo cresce con la velocità |
| 4 | Stop durante il tracking (`bStopReq` / E-Stop di controllo) | gruppo si ferma, sessione rilasciata (`bTrkSess` FALSE), ripresa senza riposizionamento manuale |
| 5 | Pausa/resume a tracking attivo | job congelato, item resta `Reserved`, ripresa con nuova sessione |
| 6 | Feed non cablata (`bUsed = FALSE`) con `g_eTrkMode = 1` | quella feed resta in fallback (nessun errore 201/202) |
| 7 | TC-19 (guida) ripetuto con 2 robot sulla stessa FEED in nativo | nessuna doppia prenotazione, guardia zona attiva |
| 8 | `ConveyorDistance = 0` forzato (solo test) | errore 9006 lato FW → errore 201 SmartPick, robot in Fault (atteso) |

Codici errore nuovi / New error codes (via `uiErrId` → `EnterFault(1)`):
`201` = sessione di tracking rifiutata dal FB (opzione/asse/distanza),
`202` = sessione non entrata in sync entro 2 s (watchdog).
/ 201 = tracking session rejected by the FB, 202 = session did not engage
within 2 s (watchdog).

---

## 2.6 v1.4 — Posa tracciata nativa / Native tracked place

La stessa macchina a sessioni della presa serve ora anche la posa: su un
nastro di uscita con frame cablato si apre una **seconda sessione**
`MC_TrackConveyorBelt` e la discesa (`Place`) e il distacco (`Retreat`)
seguono la vaschetta in movimento.
/ The same session machinery of the pick now serves the place: on an
outfeed with a wired belt frame a **second** `MC_TrackConveyorBelt`
session is opened and the place descent (`Place`) and lift-off
(`Retreat`) follow the moving tray.

**Selettore / Selector:**

```iecst
GVL_SP_Fw.g_eTrkMode        := 1;     (* prerequisito globale / global prerequisite *)
GVL_SP_Fw.g_abPlaceTrack[7] := TRUE;  (* posa tracciata sull'uscita 7 / tracked place on outfeed 7 *)
```

- Politica completa / full policy: `g_eTrkMode = 1` AND `g_abPlaceTrack[i]`
  AND frame cablato / wired (calcolata in `SP_Robot.CompBeltTargets` con
  `bPlaceSel = TRUE`). Condizione mancante → posa statica cut-off, mai
  errori. Stato visibile su `g_astRobStat[iR].bTrkPlace`.
  / Missing condition → static cut-off place, never a fault. Live flag in
  `g_astRobStat[iR].bTrkPlace`.
- **Dati di cattura / Capture data:** gli slot dei pattern entrano nella
  coda dell'uscita come record `bTarget` con `rBeltCap`/`rEncCap`/`p2World`
  (come gli item di presa); `Dispatch.StoreItem` (ramo posa) copia lo
  snapshot in `ST_SP_JobItem.stTgt` e `CompPlaceTargets` ne deriva
  `InitialObjectPosition` + mirror PCS slot-relative (stessa matematica
  della presa, chiusa a catena).
  / Pattern slots enter the outfeed queue as `bTarget` records carrying the
  same capture fields as pick items; the place branch of `StoreItem` keeps
  the snapshot in `stTgt` and `CompPlaceTargets` derives
  `InitialObjectPosition` + slot-relative PCS mirrors (same closed-chain
  math as the pick).
- **Cambio asse / Axis handover:** `m_iFeedNow` passa al feed di posa, quindi
  `ioaBelt[m_iFeedNow]` seleziona automaticamente l'asse encoder
  dell'uscita; l'avvicinamento statico (`MovePlace`) chiude la sessione di
  presa prima che si apra quella di posa.
  / `m_iFeedNow` switches to the place feed so `ioaBelt[m_iFeedNow]`
  selects the outfeed encoder axis; the static place approach closes the
  pick session before the place session opens.
- **Posa sincronizzata / Cluster place:** resta statica per progetto
  (slot su due vaschette = una sessione non basta); il ramo sync azzera
  esplicitamente la richiesta tracciata.
  / Stays static by design (slots may span two trays); the sync branch
  explicitly clears the tracked request.
- **Config d'esempio / Example configs:** `12_Application/CONFIG_EXAMPLES_IT-EN.md`
  (otto configurazioni ST in `PRG_SP_ConfigInit`; le 3 e 4 sono belt-to-belt).

Test aggiuntivi di collaudo / Additional commissioning tests:

| # | Test | Criterio / Criterion |
|---|------|----------------------|
| 9 | Posa tracciata a 0.2 m/s su uscita cablata | slot raggiunto in movimento, offset medio ≤ ±2 mm |
| 10 | `g_abPlaceTrack[i] = FALSE` sulla stessa cella | posa statica senza errori (nessuna sessione aperta) |
| 11 | Uscita senza asse encoder con selettore ON | fallback statico automatico, nessun errore 201/202 |
| 12 | Pausa/stop durante posa tracciata | sessione rilasciata, ripresa senza riposizionamento manuale |

---

## 3. Nota di architettura / Architecture note

L'adattatore `SP_RobMotion` isola **tutte** le chiamate firmware di
movimento. L'integrazione v1.3 ha toccato:

1. `FB_SP_RobMotion`: istanza `m_fbTrk : MC_TrackConveyorBelt`, sessione
   (open/wait/release), routing PCS/MCS delle mosse, watchdog, errori 201/202;
2. `FB_SP_Robot`: `SetBeltFrames` (frame nastro per feed), `CompBeltTargets`
   (geometria PCS, v1.4: anche lato posa con `bPlaceSel`), `MvToBelt`
   (bersaglio doppio mondo/PCS), FSM `TrackPick`/`Depart` (presa) e
   `Place`/`Retreat` (posa, v1.4) via `MvToBelt`, pass-through dati al body;
3. `PRG_SP_TaskFast`: `ioaBelt := g_aAxisEnc` per i 4 robot + 4 chiamate
   `SetBeltFrames`;
4. `GVL_SP_Fw`: `g_eTrkMode` + `g_abPlaceTrack` (v1.4);
5. `DUT_SP_RobotTypes`: `ST_SP_BeltFrame`, stand-in `ST_SP_TrkOpt`/`ST_SP_TrkSyncIn`,
   `ST_SP_JobItem.stTgt` + `ST_SP_RobStat.bTrkPlace` (v1.4).

Nessuna modifica a FSM di produzione, dispatcher, code, visione, pattern:
il pattern adattatore mantiene il costo dell'integrazione contenuto e la
simulazione (`g_bSim := TRUE`) continua a girare senza firmware.
/ No changes to the production FSM, dispatcher, queues, vision, patterns:
the adapter pattern keeps the integration contained and the simulation
(g_bSim := TRUE) keeps running without firmware.

---

## 4. v1.2 — Override velocità live (R-05b, 10 minuti / 10-minute task)

La crash prevention avanzata (`SP_Collision`) produce un fattore di scala
velocità per robot (`rVelScale`, 0.1..1.0) che `PRG_SP_TaskFast` passa a
`SP_Robot` e che il body applica al motion adapter ad ogni ciclo. In
modalità simulazione il fattore è già efficace. Sul target reale:

/ The advanced collision guard produces a per-robot velocity scale
(`rVelScale`, 0.1..1.0) wired by PRG_SP_TaskFast into SP_Robot and applied to
the motion adapter every cycle. It is already effective in simulation. On
the real target:

1. Individuare nel Library Repository il FB di override velocità del gruppo
   (nome atteso tipo `MC_GroupOverride` / `GroupOverride` / equivalente
   MotionAPI iC9200).
   / Locate the group velocity-override FB in the Library Repository.
2. Aprire `08_Robot/FB_SP_Robot.st`, body, chiamata `m_Mot(...)`: il punto è
   marcato `CONFIRM` accanto a `rVel := m_rVel * rVelScale` (vedi commento).
   / Open FB_SP_Robot.st, body, m_Mot call: the CONFIRM-marked point is the
   `rVel := m_rVel * rVelScale` line.
3. Variante consigliata / Recommended variant: istanziare il FB di override
   in `SP_RobMotion` (unico luogo ammesso per il firmware), abilitarlo con
   `Enable := (rVelScale < 1.0)`, `VelFactor := rVelScale` e lasciare
   invariato il percorso MC_MoveLinearAbsolute. In assenza del FB, il
   valore di Velocity passato ad ogni ciclo con Execute persistente è già
   applicato da molti stack PLCopen al volo: verificare con il test T-COL-1.
   / Instantiate the override FB inside SP_RobMotion; if unavailable, the
   per-cycle Velocity with persistent Execute is already applied live by
   most PLCopen stacks - verify with test T-COL-1.

Piano di verifica minimo / Minimum verification plan:

| Test | Procedura / Procedure | Atteso / Expected |
|------|------------------------|-------------------|
| T-COL-1 | Due robot nella stessa zona, avvicinamento a < 300 mm | Il robot a priorità inferiore rallenta in rampa |
| T-COL-2 | Avvicinamento a < 150 mm | Stop latched del robot a priorità inferiore, allarme 30..33 |
| T-COL-3 | Allontanamento > 165 mm (margine 10%) | Rilascio automatico, ripresa produzione |
| T-COL-4 | bColAdv := FALSE | Comportamento identico a v1.1 (ZoneGuard) |
