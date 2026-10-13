# SmartPick_iC — Configurazioni d'esempio in ST / Example Configurations in ST
**Versione / Version:** v1.5.0 · **File:** `12_Application/CONFIG_EXAMPLES_IT-EN.md`
**POU:** `12_Application/PRG_SP_ConfigInit.st`

Da v1.5.0 **l'intera configurazione vive in testo strutturato**: niente file CSV
da preparare, niente caricamenti da HMI. Il POU `PRG_SP_ConfigInit` scrive
direttamente i mirror di configurazione di `GVL_SP_Prod` (convogli, feed,
telecamere, pattern, batch, load sharing, zone) e pilota gli interruttori di
tracking, poi pilota il riuso del meccanismo esistente `bApplyConfig` perché
i programmi `PRG_SP_TaskMain`/`PRG_SP_TaskFast` ritrasferiscano tutto ai FB con i metodi `Configure`.

Since v1.5.0 **the entire configuration lives in structured text**: no CSV
files to prepare, no HMI loading. The `PRG_SP_ConfigInit` POU writes the
`GVL_SP_Prod` configuration mirrors directly (conveyors, feeds, cameras,
patterns, batches, load sharing, zones) plus the tracking switches, then
pulses the existing `bApplyConfig` mechanism so `PRG_SP_TaskMain` + `PRG_SP_TaskFast` re-apply
everything to the FBs via the `Configure` methods.

---

## 1. Come si applica una configurazione / How to apply a configuration

```iecst
PRG_SP_ConfigInit.iCfg   := 3;    (* 1..8, tabella qui sotto / table below *)
PRG_SP_ConfigInit.bApply := TRUE; (* impulso di salita / rising edge      *)
(* esito / outcome: PRG_SP_ConfigInit.bDone (1 ciclo) e .sMsg; .iLastCfg *)
```

All''accensione il POU applica **automaticamente** la configurazione
`iBootCfg` (default `1`, baseline) se `bAutoBoot := TRUE`: la cella nasce
configurata dal codice, senza alcuna azione operatore.

At boot the POU **automatically** applies configuration `iBootCfg` (default
`1`, baseline) when `bAutoBoot := TRUE`: the cell boots fully configured
from code, with no operator action.

> **Nota / Note:** ogni applicazione esegue prima una **cancellazione
> completa** dello spazio configurazione (template azzerati) e poi scrive la
> configurazione scelta: le configurazioni sono autonome e ripetibili, mai
> una miscela con la precedente. applicare solo a produzione ferma
> (identico al caricamento ricette / same rule as recipe loading).
> Every apply first **wipes** the whole configuration space (zeroed
> templates) and then writes the selected one: configurations are
> self-contained and repeatable, never a mix with the previous one. Apply
> only with production stopped.

---

## 2. Le otto configurazioni / The eight configurations

| # | Nome / Name | Layout | Presa / Pick | Posa / Place | Telecamere / Cameras |
|---|---|---|---|---|---|
| 1 | `baseline8` | 6 inf + 2 out (8 feed) | statica / static | statica / static | 2 simulate |
| 2 | `motopick2x2` | 2 inf + 2 out | **tracking** | statica / static | 2 Cognex |
| 3 | `belt2belt` | 2 inf + 2 out | **tracking** | **tracking** su 7 e 8 | 2 simulate |
| 4 | `mixedout` | 2 inf + 2 out | **tracking** | tracking su 7, statica su 8 | 2 simulate |
| 5 | `onerobot` *(strana)* | 6 inf + 2 out | **tracking** | statica | 1 larga (4 feed) |
| 6 | `rotrev` *(strana)* | 2 inf **reverse** + 2 out | **tracking** | **tracking** su 7 | 1 simulate |
| 7 | `onecam4feed` *(strana)* | 4 inf + 1 out | **tracking** | statica | **1 sola**, 4 regioni |
| 8 | `stress` *(strana)* | 6 inf + 2 out, zone + collisione | **tracking** | **tracking** su 7 e 8 | 2 simulate |

### Cosa c'è di "strano" nelle 5–8 / What is "strange" in 5–8

- **CFG 5 `onerobot`**: un solo robot serve **tutti** gli 8 convogli: i robot
  2–4 sono esclusi con range di lavoro vuoti su ogni feed e rapporti di
  condivisione 10 : 0.01 : 0.01 : 0.01. Una sola camera "wide" copre 4
  infeed.
  One robot serves **all eight** conveyors: robots 2–4 are excluded via
  empty work ranges on every feed and share ratios 10 : 0.01 : 0.01 : 0.01.
  A single wide camera covers 4 infeeds.
- **CFG 6 `rotrev`**: nastri di presa in **direzione inversa** (`iDir = -1`
  su convoglio e feed), vaschetta 3×3 con **slot ruotati di 90°**
  (`rRotStep = 90.0`), **2 livelli** (`rLayerH = 120`), outfeed 7
  ruotato di 15° nel frame mondo (`stWorld.rRot = 15.0`) e posa
  tracciata: stress completo della matrice di trasformazione.
  Reverse **belt direction** on the pick feeds (`iDir = -1` on conveyor and
  feed), 3×3 tray with **90°-rotated slots** (`rRotStep = 90.0`),
  **2 layers** (`rLayerH = 120`), outfeed 7 skewed 15° in the world frame
  (`stWorld.rRot = 15.0`), tracked place: full transform-matrix stress.
- **CFG 7 `onecam4feed`**: **una sola telecamera** guarda **quattro
  infeed** con quattro **regioni diverse** (`astMap`: y 0–150 / 150–300 /
  300–450 / 450–600) e distanze di trigger e velocità di riferimento
  per-feed; tre batch ad alto mix (3/2/3 tipi) con tre politiche di
  trigger diverse (Distance / Sensor / BatchStart).
  **One single camera** watches **four infeeds** through four **different
  regions** (`astMap`: y 0–150 / 150–300 / 300–450 / 450–600) with
  per-feed trigger distances and reference speeds; three high-mix batches
  (3/2/3 types) with three different trigger policies.
- **CFG 8 `stress`**: matrice di velocità 200–1200 u/s, finestre strette
  (350), zone interlock ON (feed 1–3 = zona 1, 4–6 = zona 2),
  **collisione avanzata ON** (`bColAdv`), resilienza ON, priorità batch
  **invertite** (qty 15 → priorità 100, qty 64 → priorità 1), tutti e tre
  i trigger batch contemporaneamente, belt-to-belt su entrambe le uscite.
  Speed matrix 200–1200 u/s, tight windows (350), zone interlock ON
  (feeds 1–3 = zone 1, 4–6 = zone 2), **advanced collision ON**
  (`bColAdv`), resilience ON, **inverted** batch priorities (qty 15 →
  priority 100, qty 64 → priority 1), all three batch trigger policies at
  once, belt-to-belt on both outfeeds.

---

## 3. Configurazioni 1–3 come riferimento dati / Configurations 1–3 as data reference

Le configurazioni 1, 2 e 3 **riproducono esattamente i dati delle ex
ricette CSV** `Demo_Sim`, `Demo_Line1` e `Demo_Belt2Belt` (rimosse in
v1.5.0): stesso layout, stessi valori. Le anchor di regressione sono
verificate da `scripts/sp_cfg_test.py`.

Configurations 1, 2 and 3 **reproduce the data of the former CSV recipes**
`Demo_Sim`, `Demo_Line1` and `Demo_Belt2Belt` (removed in v1.5.0): same
layout, same values. The regression anchors are verified by
`scripts/sp_cfg_test.py`.

Quote e convenzioni (vale per tutte le configurazioni / valid for all):
- unità utente = **mm** (velocità in mm/s, distanze in mm);
- **tutte le rotazioni in GRADI** (`rRotStep`, `stWorld.rRot`: es. 90° =
  `90.0`, mai 1.5708); le funzioni trigonometriche IEC (SIN/COS/ATAN,
  radianti per standard) ricevono la conversione `GC_DEG2RAD` al punto di
  chiamata — la convenzione utente resta sempre gradi;
- timeout in `T#...` (es. `T#8s` presa, `T#30s` vaschette);
- `astCalib` preimpostata **identità** (`rScale = 1`, `bValid = TRUE`)
  così le camere simulate funzionano subito; sulla cella reale si raffina
  con `SP_Calib2D`.
- user units = **mm** (speeds mm/s, distances mm); **ALL rotations in
  DEGREES** (`rRotStep`, `stWorld.rRot`: 90° = `90.0`, never 1.5708); IEC
  trig functions (SIN/COS/ATAN, radian-based by standard) get an explicit
  `GC_DEG2RAD` conversion at the call site — the user-facing convention
  stays degrees; timeouts as `T#...` literals; `astCalib` pre-filled
  **identity** so the simulated cameras work out of the box, refine on
  the real cell with `SP_Calib2D`.

---

## 4. Come si sceglie presa/posa tracking o statica / How pick/place tracking is selected

La modalità resta decisa **ad ogni movimento** dagli interruttori runtime
(scritti da ogni configurazione, modificabili poi anche da HMI):

The mode is still decided **per move** by the runtime switches (written by
every configuration, editable later from the HMI as well):

| Variabile / Variable | Campo / Scope | Valori / Values |
|---|---|---|
| `GVL_SP_Fw.g_eTrkMode` | **Presa / Pick** (globale) + prerequisito posa | `0` = statica · `1` = tracking nativo |
| `GVL_SP_Fw.g_abPlaceTrack[i]` | **Posa / Place** per outfeed `i` | `FALSE` = statica · `TRUE` = tracking |

```
posa tracciata su i / tracked place on i  ⇔  g_eTrkMode = 1
                                             AND g_abPlaceTrack[i] = TRUE
                                             AND feed i cablato / wired
```

Se manca una condizione: posa **statica** (fallback, mai errore). Stato
reale in `g_astRobStat[iR].bTrkPlace`. La posa sincronizzata multi-coppa
(R-07) resta statica per progetto. / If any condition is missing the place
is **static** (fallback, never a fault); live state in `bTrkPlace`; the
synchronized cluster place stays static by design.

---

## 5. Validazione / Validation

1. Importare il pacchetto secondo `00_ImportOrder.st` (v1.5.0) / import
   the package per `00_ImportOrder.st`.
2. `g_bSim := TRUE` (tutte le configurazioni lo impostano) / all
   configurations set it.
3. Avviare: la CFG 1 è attiva di default / start: CFG 1 is active by
   default. Per le altre: `iCfg` + impulso `bApply` / otherwise set `iCfg`
   and pulse `bApply`.
4. Verificare `bDone`/`sMsg`/`iLastCfg` e in HMI i mirror (feed usati,
   `bTrkPlace`, allarmi). / check `bDone`/`sMsg`/`iLastCfg` and the HMI
   mirrors.
5. Offline: `python3 scripts/sp_cfg_test.py` → 1322 check PASS sulle 8
   configurazioni (schema, integrità referenziale, anchor di regressione).
6. Sul reale: seguire `Firmware/FW_PATCH_ConveyorTracking_IT-EN.md` per le
   conferme enum/struct del tracking (le stesse 4 della presa).

---

## 6. E i CSV? / What about the CSVs?

I CSV **non sono più parte della configurazione**: sono rimasti solo come
**backup/restore opzionale a runtime** (esportazione HMI dei layout tarati
via `SP_RecipeMgr` + `SP_FileIo`). Il formato è documentato in
`Recipes/README_Recipe_IT-EN.md` e validabile con
`Recipes/SP_RecipeCheck.py`. Nessun CSV è richiesto per operare il sistema.

CSV files are **no longer part of the configuration**: they remain only as
an **optional runtime backup/restore** (HMI export of tuned layouts via
`SP_RecipeMgr` + `SP_FileIo`). The format is documented in
`Recipes/README_Recipe_IT-EN.md`, validatable with
`Recipes/SP_RecipeCheck.py`. No CSV is required to run the system.
