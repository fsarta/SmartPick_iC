# SmartPick_iC — Formato ricette (SOLO backup opzionale) / Recipe Format (OPTIONAL backup only)
**Formato:** `#SmartPick_iC Recipe v2` (SP_RecipeMgr, modulo 10_Persistence)
**Target:** Yaskawa iC 9226M-EC — iCube Engineer
**Stato / Status (v1.7.0):** opzionale / optional

> **v1.7.0 — unità / units:** distanze in **mm**, TUTTE le rotazioni in
> **GRADI** (`FEED rot`, `PATT rotstep/bth`: 90° = `90.0`, mai 1.5708).
> Il token CAM `thdeg` diventa `thinrad` (0 = gradi, 1 = radianti).
> I file **v1 (radianti) sono RIGETTATI** all'import (bErr): riesportare
> dalla HMI o convertire a mano i valori angolari.
> / v1.7.0 units: distances in **mm**, ALL rotations in **DEGREES**
> (`FEED rot`, `PATT rotstep/bth`: 90° = `90.0`, never 1.5708). The CAM
> token `thdeg` becomes `thinrad` (0 = degrees, 1 = radians). **v1 files
> (radians) are REJECTED** on import (bErr): re-export from the HMI or
> hand-convert the angle values.

---

## 0. Da v1.5.0: la configurazione è in ST / Since v1.5.0: configuration is in ST

La configurazione del sistema **non passa più dai CSV**: vive nel POU ST
`12_Application/PRG_SP_ConfigInit.st` (otto configurazioni d'esempio,
vedi `12_Application/CONFIG_EXAMPLES_IT-EN.md`). Nessun file è richiesto
per operare la cella.

The system configuration **no longer flows through CSV files**: it lives in
the ST POU `12_Application/PRG_SP_ConfigInit.st` (eight example
configurations, see `12_Application/CONFIG_EXAMPLES_IT-EN.md`). No file is
required to run the cell.

Questo documento descrive il **formato CSV del backup opzionale a runtime**:
l'operatore può esportare da HMI un layout tarato (`bSaveRecipe`) e
ricaricarlo dopo un reset o su un altro controllore (`bLoadRecipe`). Il
PLC stesso scrive e rilegge questi file via `SP_RecipeMgr` + `SP_FileIo`
(SysFile), quindi il formato deve restare stabile.

This document describes the **CSV format of the optional runtime backup**:
the operator can export a tuned layout from the HMI (`bSaveRecipe`) and
reload it after a reset or on another controller (`bLoadRecipe`). The PLC
itself writes and reads these files via `SP_RecipeMgr` + `SP_FileIo`
(SysFile), so the format must stay stable.

## 1. Contenuto / Contents

| File | Uso / Purpose |
|------|---------------|
| `SP_RecipeCheck.py` | Validatore offline dei CSV di backup (gemello del parser `SP_RecipeMgr.ImportLine`). / Offline validator for the backup CSVs (twin of the `SP_RecipeMgr.ImportLine` parser). |
| `README_Recipe_IT-EN.md` | Questo riferimento di formato / this format reference. |

Un CSV esportato dal PLC (`bSaveRecipe`) contiene tutte le 155 righe
(record attivi e non) ed è direttamente ricaricabile. / A PLC-exported CSV
(`bSaveRecipe`) holds all 155 rows (active and inactive records) and can be
reloaded as-is.

---

## 2. Layout di riferimento / Reference layouts

I layout delle ex-demo (oggi configurazioni 1 e 2 di `PRG_SP_ConfigInit`)
restano il riferimento geometrico di esempio:

The former demo layouts (today configurations 1 and 2 of
`PRG_SP_ConfigInit`) remain the sample geometric reference:

```
  baseline8 / motopick2x2 (quote in mm, origine mondo = pick line feed 1)

   y
 1000 +                      [FEED 7 outfeed]  (1250,1000)
  500 +   [FEED 2]                        |
    0 +-- [FEED 1] --- zona A: ROB 1+2 ---+
 -500 +   [FEED 3]                        |
-1000 +   [FEED 4..6] (x=2500) zona B: ROB 3+4
        [FEED 8 outfeed] (3750,-1000)
        x=0 ------> x=2500 -----> x=3750
```

---

## 3. Backup / restore a runtime / Runtime backup / restore

1. **Esporta / export:** HMI `sRecipeName := 'tuned_line'` + impulso
   `bSaveRecipe` → il PLC scrive `/recipes/tuned_line.csv` (una riga per
   ciclo, non bloccante). / HMI `sRecipeName := 'tuned_line'` + pulse
   `bSaveRecipe` → the PLC writes `/recipes/tuned_line.csv` (one line per
   cycle, non-blocking).
2. **Ripristina / restore:** HMI `sRecipeName := 'tuned_line'` + impulso
   `bLoadRecipe` → il PLC legge il file riga per riga e a import concluso
   forza `bApplyConfig` (tutti i FB riconfigurati). Stato in
   `sHmiRecipeState` (`loading...` → `loaded`).
   / HMI `sRecipeName := 'tuned_line'` + pulse `bLoadRecipe` → the PLC
   streams the file and pulses `bApplyConfig` at the end (all FBs
   reconfigured). Progress in `sHmiRecipeState`.
3. **Solo a produzione ferma** (contratto single-writer di `SP_RecipeMgr`).
   / **Only with production stopped** (`SP_RecipeMgr` single-writer
   contract).
4. Il nome ricetta è registrato nel retain (`g_Retain.SetRecipe`) per la
   continuità dopo power-failure. / The recipe name is stored in the retain
   blob for power-failure continuity.

Validazione di un file esterno / validate an external file:

```bash
python3 SP_RecipeCheck.py tuned_line.csv
```

---

## 4. Formato dei record / Record format

Parser **posizionale**: l'ordine dei token è fisso; separatore `,`; decimali
con `.`; nessuno spazio; max 200 caratteri per riga; solo ASCII.
/ **Positional** parser: token order is fixed; separator `,`; decimals use
`.`; no spaces; 200-char line limit; ASCII only.

| Record | Token | Significato / Meaning |
|--------|-------|----------------------|
| Header | `#SmartPick_iC Recipe v2,<nome>` | Deve essere la **prima** riga; `<nome>` ≤ 32 caratteri, senza virgole. Il PLC accetta solo `v2` (gradi): un file `v1` produce `bErr` all'header. / Must be the **first** line; `<name>` ≤ 32 chars, no commas. The PLC accepts `v2` (degrees) only: a `v1` file raises `bErr` at the header. |
| `CONV` | `n, scale, dir, maxspd, winstart, winlen, slowahead, stopahead, slowf, drive, anach` | Linea fisica. `scale` = mm/impulso encoder; `dir` 0=−1, 1=+1; `drive` 0=Analogico(VFD), 1=Asse servo (MC_MoveVelocity), 2=Esterno; `anach` canale analogico se drive 0. / Physical conveyor. `scale` = mm per encoder count; `dir` 0=−1, 1=+1; `drive` 0=Analog(VFD), 1=Servo axis (MC_MoveVelocity), 2=External; `anach` = analog channel when drive 0. |
| `FEED` | `n, dir, winstart, winlen, pickahead, timeout_ms, zbelt, dx, dy, rot` | Linea tracciata. Finestra di tracciamento [mm], `pickahead` = distanza di prenotazione a monte della pick line, `zbelt` = quota superficie nastro nel mondo, `dx/dy/rot` = trasformazione linea→mondo (compensazione disallineamento; `rot` in **gradi**). / Tracked feed. Tracking window [mm], `pickahead` = upstream reservation cut-off, `zbelt` = belt surface height in world, `dx/dy/rot` = feed→world transform (misalignment compensation; `rot` in **degrees**). |
| `CAM` | `n, drv, ip, port, trig, trigdist, refspd, maxitems, thinrad, minscore, delay_ms` | `drv` 0=Cognex, 1=Keyence, 2=GenericTCP, 3=Simulata; `trig` 0=Distanza, 1=Esterno, 2=Intervallo, 3=Manuale; `trigdist/refspd` = distanza di trigger e velocità di riferimento (auto-scaling ×0.5..×2); `thinrad` 0=theta in gradi (default), 1=radianti (convertiti); `minscore` 0..1. / `drv` 0=Cognex, 1=Keyence, 2=GenericTCP, 3=Simulated; `trig` 0=Distance, 1=External, 2=Interval, 3=Manual; `trigdist/refspd` = trigger distance and reference speed (auto-scaling ×0.5..×2); `thinrad` 0=theta in degrees (default), 1=radians (converted); `minscore` 0..1. |
| `CAMMAP` | `n, k, feed, ymin, ymax, trigd, refspd` | Regione della camera n assegnata alla feed: item con Y camera in `[ymin..ymax]` → feed. `k` = slot 1..8. Ogni riga può ridefinire `trigd/refspd` per la singola feed. / Camera n region assigned to a feed: item with camera Y inside `[ymin..ymax]` → feed. `k` = slot 1..8. Each row can override `trigd/refspd` per feed. |
| `PATT` | `n, rows, cols, dx, dy, rotstep, bx, by, bth, layers, layerh, zbase, trigdist` | Griglia di deposito nel frame feed (u trasversale, v a monte). `rows×cols ≤ 16`; `layers ≤ 4`; `rotstep/bth` in **gradi** (es. `90.0` = quarto di giro per slot); `zbase` = quota mondo strato 0; `trigdist` = passo di ripetizione nel modo Distanza. / Placement grid in the feed frame (u across, v upstream). `rows×cols ≤ 16`; `layers ≤ 4`; `rotstep/bth` in **degrees** (e.g. `90.0` = quarter turn per slot); `zbase` = world Z of layer 0; `trigdist` = repetition pitch in Distance mode. |
| `BATCH` | `n, outfeed, patt, qty, trig, priority` | `trig` 0=Distanza (nuova vaschetta ogni `PATT.trigdist`), 1=Sensore (barriera `abTraySensor`), 2=BatchStart (pallet statico, 1 sola istanza); `priority` −100..100 (più alto = prima). / `trig` 0=Distance (new tray every `PATT.trigdist`), 1=Sensor (`abTraySensor` barrier), 2=BatchStart (static pallet, single instance); `priority` −100..100 (higher = sooner). |
| `BATCHMIX` | `n, k, type, cnt` | Mix tipi per strato: `cnt` slot del tipo `type`; Σcnt per strato ≤ `rows×cols`; `type` 0 = voce vuota. / Type mix per layer: `cnt` slots of `type`; Σcnt per layer ≤ `rows×cols`; `type` 0 = empty entry. |
| `SHARE` | `feed, strat, match, strict, pickbias, outfeedmap` | Strategia di bilanciamento della feed: 0=Organic, 1=Greedy, 2=Balanced, 3=Manual; `match` 0=Matched, 1=Unmatched, 2=Mixed; `outfeedmap` = mappa presa→uscita (0 = nessuna). / Per-feed balancing strategy: 0=Organic, 1=Greedy, 2=Balanced, 3=Manual; `match` 0=Matched, 1=Unmatched, 2=Mixed; `outfeedmap` = infeed→outfeed map (0 = none). |
| `SHARER` | `feed, robot, ratio, rangef, ranget, tmask, manual` | Idoneità del robot k sulla feed: `ratio` > 0 (Balanced); `[rangef..ranget]` = finestra a monte in mm **sull'offset della linea** (0,0 = robot disabilitato su quella feed); `tmask` = maschera a 32 bit dei tipi consentiti (bit i−1 = tipo i, 4294967295 = tutti); `manual` = matrice fissa per la strategia Manual. / Robot k eligibility on the feed: `ratio` > 0 (Balanced); `[rangef..ranget]` = upstream window in mm **on the line offset** (0,0 = robot disabled on that feed); `tmask` = 32-bit allowed-type mask (bit i−1 = type i, 4294967295 = all); `manual` = fixed matrix for the Manual strategy. |

**Nota differenza ST / ST difference note:** a differenza dell'import CSV
(merge incrementale: record assente = oggetto disabilitato), il POU
`PRG_SP_ConfigInit` **cancella prima tutto** e poi scrive la configurazione
scelta, quindi le configurazioni ST sono sempre complete. / Unlike the CSV
import (incremental merge: absent record = object left disabled), the
`PRG_SP_ConfigInit` POU **wipes everything first** and then writes the
selected configuration, so ST configurations are always complete.

---

## 5. Cosa NON è nel backup / What is NOT in the backup

Per design (roadmap R-03 della guida architetturale) restano **fuori** dal
formato e vanno configurati altrove:
/ By design (roadmap item R-03 of the architecture guide) the following stay
**outside** the format and are configured elsewhere:

| Dato / Data | Dove / Where |
|-------------|--------------|
| Calibrazione camera→feed (`astCalib`) e `stWorld.rScale` | Procedura `SP_Calib2D` + retain (n-point similarity); nelle config ST preimpostata identità. / `SP_Calib2D` procedure + retain; identity default in the ST configs. |
| Commissioning robot/attrezzi: velocità, tempi grip, geometria ventose, retry (`g_astRobCfg`) | Default `FUN_SP_RobCfgDefault` + editor HMI. / `FUN_SP_RobCfgDefault` defaults + HMI editor. |
| Protocollo camera: `sTrigStr`, `sDelim`, `uiIdxType/X/Y/Th/Score`, `sEndTok`, `sSendFmt` | **Auto-preset dai driver**: Cognex `TRIG`, Keyence `R`, delimitatore `,`, token 1..5 (vedi `FB_SP_DrvCognex/Keyence`); le config ST li impostano esplicitamente dove serve. / **Auto-preset by the drivers**; the ST configs set them explicitly where needed. |
| Abilitazioni outfeed nel wiring (`bIsOutfeed`, `abiFeedOn[7..8] := FALSE`) | Cablato in `PRG_SP_TaskFast` (feed 7..8 = uscite). / Hard-wired in `PRG_SP_TaskFast` (feeds 7..8 = outfeeds). |

---

## 6. Regole per la modifica manuale / Hand-editing rules

1. **Niente commenti a metà file**: ogni riga che inizia con `#` viene
   interpretata come intestazione e **rinomina** la ricetta. Un solo header,
   in prima riga. / **No mid-file comments**: any line starting with `#` is
   parsed as a header and **renames** the recipe. One header only, first row.
2. Mantenere il nome file = nome header = `sRecipeName` HMI.
   / Keep file name = header name = HMI `sRecipeName`.
3. Nessun BOM, nessun CRLF misto (CR e LF sono entrambi accettati), nessun
   spazio attorno alle virgole. / No BOM, no mixed line endings (CR and LF
   are both accepted), no spaces around commas.
4. Indici partono da **1**; gli id non usati si omettono (non si scrivono a
   zero). / Indices are **1-based**; omit unused ids (do not write zeros).
5. Dopo ogni modifica rieseguire `SP_RecipeCheck.py`.
   / Re-run `SP_RecipeCheck.py` after every edit.
6. Variazioni geometriche (winstart/winlen/zbelt/transform) richiedono
   ricalibrazione e nuovo dry-run: vedere TC-07..TC-10 della guida.
   / Geometry changes (winstart/winlen/zbelt/transform) require recalibration
   and a new dry run: see TC-07..TC-10 of the guide.

### Esempi di partizionamento / Partitioning examples

* **Metà linea per robot** (2 robot sulla stessa feed): robot A
  `rangef=0, ranget=300`; robot B `rangef=300, ranget=600` — l'idoneità è
  valutata sull'offset a monte dell'offerta più vicina.
  / **Half-belt per robot** (2 robots on one feed): robot A
  `rangef=0, ranget=300`; robot B `rangef=300, ranget=600` — eligibility is
  evaluated on the upstream offset of the nearest offer.
* **Tipi per robot**: robot 1 solo tipi 1..8 → `tmask = 000000FF` hex =
  `255`; robot 2 tipi 9..16 → `65280`. Con `match=2` (Mixed) un'offerta non
  coperta passa comunque al secondo giro senza maschera.
  / **Type ownership**: robot 1 types 1..8 only → `tmask = 0x000000FF` =
  `255`; robot 2 types 9..16 → `65280`. With `match=2` (Mixed) an unmatched
  offer is retried in a second pass without the mask.
* **Bilanciamento**: `strat=2` (Balanced) e `ratio` 2.0/1.0/1.0/1.0 ⇒ il
  robot 1 prende ~40% del lavoro. / **Load sharing**: `strat=2` (Balanced)
  with `ratio` 2.0/1.0/1.0/1.0 ⇒ robot 1 takes ~40% of the work.
