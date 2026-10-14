# SmartPick_iC — CSV Variabili per importazione diretta in iCube Engineer

Questo documento descrive il pacchetto CSV generato automaticamente a partire dai
73 fogli Structured Text del progetto. I file seguono **esattamente** il formato
di esportazione/importazione della Variable Table di iCube Engineer (formato
verificato sul file di esempio `testVar.csv`).

---

## 1. Formato del file (12 colonne, separatore `;`)

Intestazione (identica in ogni file):

```
Group;Name;DataType;Usage;IsTranslate;Comment;InitValue;AccessSpecifier;IsRetain;IsConstant;IsOpc;Address
```

| Colonna | Contenuto | Valori usati in questo pacchetto |
|---|---|---|
| `Group` | Blocco di dichiarazione ST di appartenenza | `VAR`, `VAR_INPUT`, `VAR_OUTPUT`, `VAR_IN_OUT`, `VAR CONSTANT`, `VAR RETAIN` |
| `Name` | Nome variabile | come nel sorgente ST |
| `DataType` | Tipo di dato | `BOOL`, `UINT`, `LREAL`, `STRING(64)`, `ARRAY[1..8] OF REAL`, `ST_SP_TrkItem`, `ET_SP_RetCode`, ... |
| `Usage` | Classe di utilizzo iCube | `Input`, `Output`, `InOut`, `Local`, `Global` (Global = dentro GVL) |
| `IsTranslate` | Flag traduzione HMI | `False` |
| `Comment` | Commento inglese del sorgente | testo (virgolettato RFC-4180 se contiene `;` o `"`) |
| `InitValue` | Valore iniziale ST | `TRUE`, `0`, `450.0`, `T#150ms`, `'testo'`, `UINT#10`, ... (vuoto se assente) |
| `AccessSpecifier` | Specificatore di accesso | `None` |
| `IsRetain` | Flag RETAIN | `True` solo per `VAR RETAIN` |
| `IsConstant` | Flag CONSTANT | `True` solo per `VAR CONSTANT` |
| `IsOpc` | Flag esposizione OPC | `False` |
| `Address` | Mappatura process data (%I/%Q) | vuoto: il mapping PDI si assegna in iCube Hardware/Role Picker |

Esempio di riga (identico nello stile a `testVar.csv`):

```
VAR_INPUT;StartCycle;BOOL;Input;False;;;None;False;False;False;
VAR CONSTANT;GC_DUP_TOL_MM;LREAL;Global;False;Duplicate item merge tolerance [mm];25.0;None;False;True;False;
```

**Codifica:** UTF-8, terminatori riga CRLF (standard Windows/iCube Engineer).

---

## 2. Mapping Structured Text → CSV

| Dichiarazione ST | Group | Usage | IsRetain | IsConstant |
|---|---|---|---|---|
| `VAR ... END_VAR` (locale) | `VAR` | `Local` | `False` | `False` |
| `VAR ... END_VAR` (dentro GVL) | `VAR` | `Global` | `False` | `False` |
| `VAR_INPUT` | `VAR_INPUT` | `Input` | `False` | `False` |
| `VAR_OUTPUT` | `VAR_OUTPUT` | `Output` | `False` | `False` |
| `VAR_IN_OUT` | `VAR_IN_OUT` | `InOut` | `False` | `False` |
| `VAR CONSTANT` | `VAR CONSTANT` | `Local` oppure `Global` (GVL) | `False` | `True` |
| `VAR RETAIN` | `VAR RETAIN` | come sopra | `True` | `False` |
| campo `STRUCT` (DUT) | `STRUCT` | `Local` | — | — |
| literal `ENUM` (DUT) | `ENUM` | `Local` | — | — |

> **Nota su campi STRUCT e literal ENUM:** sono riportati per completezza
> documentale nelle cartelle `DUT_Reference/` e nel master. In iCube Engineer i
> DUT (STRUCT/ENUM) si creano nel **DUT editor**, non tramite import CSV della
> variable table: usare quei file come trascrizione puntuale.

> **Nota `Usage=External` / `Group` indipendenti:** nel formato iCube le due
> colonne sono indipendenti (variabili collegate a device possono avere
> `Group=VAR_INPUT` e `Usage=External`). SmartPick_iC non usa variabili
> collegate a device in codice (il mapping I/O avviene in Hardware view), quindi
> il mapping è canonico come in tabella.

---

## 3. Struttura della cartella `Variables/`

```
Variables/
├── gen_var_csv.py            Generatore (rigenerabile dopo ogni modifica al codice)
├── README_VarCsv_IT.md       Questo documento
├── Vars_MASTER.csv           Registro di TUTTE le 2213 variabili (con colonna
│                             aggiuntiva Worksheet;ScopeKind;ScopeName)
├── ByWorksheet/              Un CSV per ogni foglio .st (documento d'insieme)
│   ├── GVL_SP_Const.csv
│   ├── FB_SP_ItemQueue.csv
│   └── ...
├── 01_Common/ ... 15_Professional/     CSV "import-ready" per modulo:
│   ├── GVL_SP_Const.csv                ← tabella variabili del GVL
│   ├── FB_SP_ItemQueue.csv             ← interfaccia del FB (VAR_IN/OUT/IN_OUT + VAR)
│   ├── FB_SP_ItemQueue.M.Add.csv       ← variabili del METHOD Add
│   ├── FUN_SP_Clamp.csv                ← variabili della FUNCTION
│   └── PRG_SP_TaskMain.csv             ← variabili del PROGRAM
└── DUT_Reference/            Campi STRUCT e literal ENUM (solo riferimento)
    └── 05_Tracking/DUT_SP_TrkTypes.S.ST_SP_TrkItem.csv
```

### Conteggio generato (2213 variabili totali)

| Ambito | N. variabili | File CSV |
|---|---|---|
| GVL globali (10 GVL) | 124 | 10 |
| Interfacce FB (35 FB) | 603 | 35 |
| METHOD (209 metodi) | 592 | 209 |
| PROGRAM (4 programmi) | 115 | 4 |
| FUNCTION (40 funzioni) | 186 | 40 |
| Campi STRUCT (81 DUT) | 463 | 65 |
| Literal ENUM | 130 | 16 |
| **Totale** | **2213** | **421 + master** |

---

## 4. Procedura di importazione in iCube Engineer 2026.6

1. **Aprire il progetto** SmartPick_iC in iCube Engineer.
2. **Selezionare la tabella destinazione:**
   - per le variabili globali: la **Data List** del nodo `IEC 61131-3` (oppure
     l'editor del singolo GVL);
   - per le variabili di un POU: la **Variables table** del FB/PROGRAM/FUNCTION/METHOD.
3. **Import CSV...** dal menu contestuale (o il pulsante apposito sulla toolbar).
4. Selezionare il CSV corrispondente (es. `Variables/05_Tracking/FB_SP_ItemQueue.csv`).
5. Verificare il log nel pannello **MESSAGES** (numero di variabili importate).
6. **Ripetere per ogni file** necessario. Non serve importare `DUT_Reference/`
   né `ByWorksheet/` (sono documentazione).

### Avvertenze note (dalle release notes iCube/PLCnext)

- L'import **non sovrascrive** le variabili già esistenti: vengono aggiunte solo
  quelle nuove. Eventuali duplicati vanno rimossi manualmente.
- Il **mapping PDI/process data** non viene ripristinato dall'import: assegnare
  gli indirizzi %I/%Q (colonna `Address`) nella Hardware view o con il Role Picker.
- File CSV molto grandi possono causare errori del meta-compilatore nativo:
  importare **un file per volta** (questo pacchetto è già suddiviso per target).
- L'encoding è **UTF-8** (come i CSV generati da iCube). Se si apre il file in
  Excel per revisione, usare *Dati → Da Testo/CSV* con origine `65001 - Unicode (UTF-8)`.
- I campi con `,` `;` o `"` nel commento/valore sono virgolettati secondo
  RFC-4180 (es. `GC_ASCII95`): l'importatore iCube li gestisce nativamente.

---

## 5. Rigenerazione del pacchetto

Dopo ogni modifica ai fogli `.st`:

```bash
python3 Variables/gen_var_csv.py
```

Output atteso:

```
CSV generati : 421 file + 1 master
Variabili    : 2213
   GVL         : 124
   FB          : 603
   METHOD      : 592
   PROGRAM     : 115
   FUNCTION    : 186
   STRUCT      : 463
   ENUM        : 130
```

Il generatore (`gen_var_csv.py`) è parametrico in testa al file:
`GVL_USAGE`, `ACCESS_SPECIFIER`, `IS_TRANSLATE`, `IS_OPC`, `ADDRESS` e la
tabella `SECTION_USAGE` si adattano senza toccare la logica, se una futura
versione di iCube richiedesse valori diversi (es. `Usage=Global` alternativo
per i GVL).

---

## 6. Verifiche di qualità già eseguite

- Intestazione a 12 colonne identica a `testVar.csv`: verificata carattere per carattere.
- Terminatori riga CRLF singoli (nessun `\r\r`): verificato su tutti i 422 file.
- Ogni riga ha esattamente 12 campi (conteggio `;` con parsing RFC-4180).
- Commenti e valori iniziali con caratteri speciali virgolettati correttamente
  (es. `GC_ZONE_NONE`, `GC_ASCII95`).
- Corrispondenza dei conteggi con l'estrazione statica dei 73 fogli ST
  (nessuna variabile persa, nessun duplicato).
