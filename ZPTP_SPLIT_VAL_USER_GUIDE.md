# ZPTP_SPLIT_VAL_MIG — User Guide

2026-11-11 · program v1.33

This guide is for the migration team and the key users who run the stock and batch migration from plant 8P01 to plant 8Q01. It explains every option of the selection screen, which settings to choose for each step of the migration, how to read the result list, and how to fix what the report reports. Technical names are given in brackets, for example *Simulation (P_TEST)*, so that you can find each field on the screen and in the variants.

## 1. What the report does

ZPTP_SPLIT_VAL_MIG moves stock from plant 8P01 to the split-valuated plant 8Q01 with movement type 301 (one-step plant-to-plant transfer). Missing batches are created in 8Q01 with the attributes of the 8P01 batch and the right valuation type. Every line is logged, and the result is shown in an ALV list.

| Item | Value |
| --- | --- |
| Program | ZPTP_SPLIT_VAL_MIG |
| Start from | Transaction ZPTP_SPLIT_VAL_MIG (area menu ZPTP_SVAL_MENU), or SE38 / SA38 |
| Default plants | 8P01 (source) → 8Q01 (target) |
| Log tables | ZPTP_MOV_EXEC (movements), ZPTP_BATCH_EXT (batches) |
| Storage location mapping | ZPTP_SLOC_MAP (SM30) |
| Valuation types for project stock | ZPTP_301_VALTYPE |
| Message class | ZPTP_SPLIT_VAL |

### 1.1 Four stock types, one per run

| Stock type | What moves | Movements | Input file |
| --- | --- | --- | --- |
| 1 Unrestricted | Unrestricted stock | 301 | yes |
| 2 Blocked | Blocked stock | 343 (8P01), 301, 344 (8Q01): it arrives blocked | yes |
| 3 QI without inspection lot | Quality inspection stock not held by an open inspection lot | 321 (8P01), 301, 322 (8Q01): it arrives in quality inspection | yes |
| 4 Project stock (Q) | Unrestricted project stock, per WBS element | 301 Q to the same WBS element | no |

To migrate everything, run the report once per stock type.

**Not moved:** quality-inspection stock held by an open inspection lot (reported, message 055); sales order stock, consignment and stock at vendor (not reported); batch classification (not copied).

### 1.2 What drives the run

| | Option 1 — Split valuation materials | Option 2 — Non split valuation materials | Project stock (type 4) |
| --- | --- | --- | --- |
| Driven by | **The input file** | **SAP stock of 8P01** | **SAP project stock of 8P01** |
| The file | Says what to move: material, batch, valuation type, quantity | Only says which materials to **leave out** | Not read |
| Valuation type | From the file | None (the material must not be split-valuated in 8Q01) | From the batch in 8Q01, else from ZPTP_301_VALTYPE |
| Stock of 8P01 not in the file | Added and posted with a warning (Full mode), unless "Only file items in src plant" is ticked | This is what is moved | — |

Option 1 moves what the file defines; option 2 moves everything else that is not split-valuated in 8Q01. Run with the same file, they cover the whole plant except split-valuated materials missing from the file.

## 2. Before you run it

### 2.1 Set-up in 8Q01

- [ ] Plant 8Q01 exists and is different from the source plant.
- [ ] ZPTP_SLOC_MAP (SM30) has one entry per storage location of 8P01 holding stock: 8P01 / source storage location → 8Q01 / target storage location. A missing entry blocks the line (024).
- [ ] Every target storage location of ZPTP_SLOC_MAP exists in 8Q01. A missing one blocks the line (023).
- [ ] Every material is extended to 8Q01, with a valuation segment for each valuation type of the file. A missing segment blocks the line (003, Full mode).
- [ ] Batch management is the same in 8P01 and 8Q01.
- [ ] Automatic creation of storage location data is allowed for movement type 301 (OMB3), or the material is already maintained in the receiving storage locations; otherwise the 301 fails with an SAP message.
- [ ] Project stock: ZPTP_301_VALTYPE has active entries for the fiscal year of the posting date.

### 2.2 The input file (stock types 1 to 3)

Build it with **ZPTP_SPLIT_VAL_MIG_UTILITY** (transaction ZPTP_SPLIT_VAL_UTIL), choosing the same stock type as the migration run. Five columns, in this order:

| Column | Content |
| --- | --- |
| MATNR | Material, with or without leading zeros |
| CHARG | Batch. NO_BATCH (or blank) for a material without batch management |
| BWTAR | Valuation type in 8Q01 |
| QUANTITY | Quantity in the base unit; point or comma for decimals, no thousands separator |
| UOM | Base unit, or blank |

```csv
MATNR;CHARG;BWTAR;QUANTITY;UOM
100234;0000004711;VT01;150,000;KG
100234;4712;VT02;80,000;KG
200987;NO_BATCH;VT01;1250,000;PC
300555;;VT02;0,000;L
```

- The header line is optional.
- **File name:** it must contain UNRESTRICTED (type 1), BLOCK (type 2), or QI but not QI_LOT (type 3). The utility proposes such names, for example `ZPTP_SPLIT_VAL_8P01_8Q01_UNRESTRICTED_20261111.csv`.
- **Batch numbers:** a numeric batch is looked up with leading zeros first (4712 → 0000004712), then without. A partly padded value (004712) matches neither form.
- **Batch numbers with "," or ".":** the batch is looked up as written first; if it does not exist in 8P01, with every comma and full stop swapped (24.105 → 24,105). The batch found in SAP is used for everything (batch creation, postings), and the list and the log show the file value (*File batch*) and the flag *Punct. swapped*. If both forms exist, the one as written is used and a warning (063) points to possible duplicate batches. If neither exists, the line fails (062) with both values in the message. The file itself is never changed.
- One batch, one valuation type.
- For each material and batch, the file total should equal the stock of the type moved in 8P01 (quantity check), unless you use "Force qty to source stock".
- For a background job, copy the file to the application server first with **ZPTP_SPLIT_VAL_MIG_UPLOAD** (transaction ZPTP_SPLIT_VAL_UPLD), or with CG3Z in text mode.

### 2.3 Authorizations

| Task | Authorization |
| --- | --- |
| Start the report | Transaction ZPTP_SPLIT_VAL_MIG in your role |
| Post movements, create or change batches | Standard checks of BAPI_GOODSMVT_CREATE, BAPI_BATCH_CREATE, BAPI_BATCH_CHANGE (plants 8P01 and 8Q01) |
| Read a server file | S_DATASET for the path |
| Release a background job | S_BTCH_JOB (otherwise release it in SM37) |
| Delete a RUN_ID, empty the logs | S_TABU_NAM, activity 02, ZPTP_MOV_EXEC and ZPTP_BATCH_EXT |

### 2.4 Timing

- Agree a freeze: no goods movements in 8P01 between the final simulation and the real run, otherwise the quantity check fails (004).
- The posting period of the posting date must be open (MMPV / OB52).

## 3. The selection screen, option by option

The screen has five blocks, in this order: **Execution mode**, **Run control** (with **Input file** and **Maintenance** inside it), **Processing option**, **Stock type transferred**, **Organizational data**. The checks of the screen run only when you execute (F8, background job, print), never while you fill it in.

### 3.1 Block "Execution mode"

#### Online - post line by line (P_ONL)

The report reads and checks the file exactly as in Background mode, but **posts nothing by itself**. The ALV list shows one row per line with status **R** (ready) and the quantity that would be posted. You then post from the list:

1. Tick the lines to post in the selection column on the left. **Double-click** a row to tick every row of that material at once (the other rows are unticked); double-click it again to untick.
2. Press **Post**. One confirmation popup shows what will be posted ("Post line 12: 150 KG of material 100234 batch 0000004711 …" for one line, "Post 8 lines …" for several, with the number of ticked lines that will be skipped).
3. The lines are posted one after the other, in file order. Each line goes through every check of Background mode, is logged under the same RUN_ID, and its row is replaced by the result rows (green when posted, red when it failed). A message gives the totals: "5 line(s) posted, 1 failed, 2 skipped".

Good to know:
- Lines that cannot be posted (rejected by a file check, zero quantity) show their result straight away.
- A line already posted is skipped. A line that **failed can be posted again** once you have fixed the cause.
- **Simulation does not apply**: the Simulation checkbox disappears when you choose Online, and every Post is real. The confirmation popup is your safeguard.
- Online mode needs a dialog session: it cannot be combined with "Run as background job".
- Works with both processing options and all four stock types.

Use it to post a selection of materials, to post sensitive materials one by one under control, or to finish the lines left over after a background run.

#### Background - all lines (P_BGD) — default

Every line is checked and posted in one run, without any interaction. This is the standard way to run the migration, and the only way to run a simulation.

#### Run as background job (P_JOB)

With Background: F8 does not run the report in your session but schedules it as a background job started immediately (job ZPTP_SPLIT_VAL_MIG), with the same selection. The screen shows the job number and the RUN_ID. Follow the job in SM37; its spool holds the run header and the result list, and the log is in ZPTP_MOV_EXEC.

- The file must be on the application server (Input file = Application server).
- If "Delete all logs before the run" is ticked, the logs are emptied in your session first (with confirmation), not in the job.
- Use it for large files: a dialog run can hit the time-out.

#### Simulation (P_TEST) — ticked by default

Ticked: every check runs and SAP checks the movements in test mode, but **nothing is posted and no batch is created**. Lines that would be posted get status T, and Mat.Doc shows SIMULATED. Untick it for the real run.

- Stock types 2 and 3: only the first movement (343 / 321) can be simulated, because the 301 needs the stock it moves.
- Simulated runs never count as "already transferred" and never block a later real run.
- Hidden and ignored in Online mode.

#### Simulation without log (P_NOLOG) — ticked by default

Applies only with Simulation ticked (it is greyed out otherwise, and hidden in Online mode).

- **Ticked:** the simulation writes **nothing** to the log tables ZPTP_MOV_EXEC and ZPTP_BATCH_EXT. The result is only in the ALV list (in the spool for a background job): keep or export it if you need it. A RUN_ID is shown in the list header for reference but is not stored, and no sequence is used up.
- **Unticked:** the simulation is logged under its RUN_ID with the Simulation flag, like before. Use it when you want to keep the simulation (review, audit) or reprocess errors from it.
- A real run (Simulation unticked) is always logged, whatever this checkbox says.

### 3.2 Block "Run control"

#### Full validation (P_FULL) — default / Direct transfer (P_DIR)

| | Full validation | Direct transfer |
| --- | --- | --- |
| Valuation type exists in 8Q01 (003) | checked | not checked |
| File total = SAP stock (004) | checked | not checked |
| Stock of 8P01 missing from the file | added and posted with warning 010 | ignored |
| All other checks | yes | yes |

Use **Full validation** for the migration. Use **Direct transfer** only for materials agreed in advance whose split valuation is not yet active in 8Q01: the 301 then carries a valuation type only if the material is split-valuated in 8Q01. Option 2 and project stock always run their own checks and ignore this choice.

#### Deactivate qty check vs file (P_NOQTY)

Turns off the check "file total per material + batch = stock of the type moved in 8P01" (004). The lines are posted with the file quantity, as long as the stock covers it (otherwise 005). All other checks stay active. Use it when stock has moved slightly since the extract and the business accepts the file quantities.

#### Deactivate file name check (P_NOFNM)

Turns off the check that the file name matches the stock type (UNRESTRICTED / BLOCK / QI). Use it only for a file you renamed yourself and know to be right: the check protects you from posting a blocked-stock file as unrestricted stock.

#### Force qty to source stock (P_FQTY)

Ignores the quantities of the file: each material + batch of the file is transferred with its **whole stock** in 8P01 for the stock type chosen.

- Several lines for the same material + batch: the first line with a quantity takes the whole stock, the others move nothing.
- No stock in 8P01: quantity 0, status Z, no movement.
- *File Qty* still shows the file quantity; a line whose quantity changed carries warning 060 in the list until it is posted.
- The quantity check then always passes. All other checks (batch, valuation type, storage locations) still run.
- Option 1, stock types 1 to 3 only. Option 2 and project stock already move the whole stock.

Use it when the file is right for materials, batches and valuation types, but its quantities are out of date.

#### Only SAP variance >= 0 (P_SVPOS)

The list shows only the rows whose **SAP Variance** (see 6.2) is 0 or more, that is where the stock of 8P01 covers what the run wants to transfer.

- Background: only the list is filtered; every line is still processed and logged.
- Online: the hidden lines are not listed, so they **cannot be posted**. Use it to post only the batches where the stock is sufficient.

#### Only file items in src plant (P_FONLY)

Option 1 only. Ticked, the run is limited strictly to the file:

- a file line is treated only if its material is extended to 8P01 and, for a line with a batch, the batch exists in 8P01. Other lines are left out with status X (061), not as errors;
- stock of 8P01 that is **not** in the file is **not** added (no 010 / 011 rows).

Unticked, the report also picks up stock of 8P01 missing from the file (Full mode). Use it when the file is the complete, agreed scope and nothing else must move.

#### ALV status (S_STAT)

Shows only the selected statuses in the result list (F4 lists the values with their meaning; ranges and exclusions are possible). Blank shows everything. Only the list is filtered: every line is still processed and logged. In Online mode, ready lines (R) hidden by the filter cannot be posted.

### 3.3 Sub-block "Input file"

| Field | What to enter |
| --- | --- |
| Application server (P_SRV) | The file is on the SAP application server. The only choice for a background job. |
| Local file (P_LOC) — default | The file is on your PC. Dialog runs only. |
| Input file path (P_FILE) | Full path of the file. F4 lists the files of a server directory, or opens the PC file dialog. The path is case-sensitive on the server. Not needed for project stock. |
| Field separator (P_SEP) | Column separator of the file, `;` by default. |

### 3.4 Sub-block "Maintenance"

#### Run ID, blank=new (P_RUNID)

Blank: a new RUN_ID is created (HBM + date + time, for example HBM20261111143015). Filled with an existing RUN_ID: the run is added to it as the next sequence (002, 003, …). Needed for Reprocess errors and Delete run ID, and useful with "Max. materials per run" to continue where the previous run stopped.

#### Reprocess errors (P_REPRC)

Processes again only the lines in status E of the previous sequence of the RUN_ID, as a new sequence. Use it after the real run, once the causes are fixed. The "stock missing from the file" step does not run. In Online mode you can also post a failed line again directly from the list.

#### Delete run ID (P_DEL)

Deletes the log rows of the RUN_ID from ZPTP_MOV_EXEC and ZPTP_BATCH_EXT, after a confirmation. Nothing else runs and no stock moves. Refused when the run contains real postings: the log is the audit trail. Use it to clean up simulation runs.

#### Delete all logs before the run (P_CLR)

Empties both log tables completely, after a confirmation, then runs the report normally (sequences restart at 001). The log of real postings is deleted too, so use it only before the first real run, when the history is no longer needed. Needs the table authorization; cannot be combined with Reprocess errors.

### 3.5 Block "Processing option"

#### Split Valuation Materials (P_SPLIT) — default

Option 1: the lines of the file are transferred with their valuation type and quantity (see 1.2).

#### Non split valuation materials (P_NONSPL)

Option 2: every material with stock of the type moved in 8P01 that is **not in the file** is transferred with its whole stock, batch created in 8Q01 when missing, **without valuation type**.

- The file is still required: it lists the materials to leave out (any line, even a rejected one, excludes its material). An empty file is refused.
- Refused materials: split-valuated in 8Q01 (025: put it in the file and use option 1), not extended to 8Q01 (014), different batch management (026).
- Full / Direct, the quantity check, "Force qty to source stock" and "Only file items in src plant" do not apply.

#### Create batches with zero stock (P_ZBAT)

Creates in 8Q01 the batches that have **no stock** in 8P01, without posting any movement (status S, T in a simulation). Option 1: file lines with quantity 0 and a batch. Option 2: batches of 8P01 (not flagged for deletion) of materials not in the file. Unticked, a zero line stays in status Z and nothing is created.

### 3.6 Block "Stock type transferred"

| Choice | What happens |
| --- | --- |
| 1 Unrestricted stock (P_XUNR) — default | One 301 per line. |
| 2 Blocked stock (P_XBLK) | 343 in 8P01 (blocked → unrestricted), 301, 344 in 8Q01 (back to blocked). Three documents per line, each on its own rows (column Mvt type). |
| 3 QI stock without insp. lot (P_XQI) | 321 in 8P01, 301, 322 in 8Q01. Stock held by an open inspection lot stays in 8P01 (055). |
| 4 Project stock (Q) (P_XPRJ) | No file. Project stock of each material + batch + WBS element is moved with a 301 Q to the same WBS element. |

**Types 2 and 3 — when a movement fails:**
- The 301 fails: the first movement is reversed automatically, the line ends in E and can be reprocessed. If the reversal fails too, the message says which movement to post manually.
- The last movement (344 / 322) fails: status W; the stock is unrestricted in 8Q01: post the 344 or 322 yourself in MIGO for the quantities shown.

**Type 4 — project stock:**
- SAP drives the run, for split-valuated and non-split materials alike; the split / non-split option is ignored, and no file is read (a file of option 1 has no effect).
- Valuation type: the one of the batch in 8Q01; a batch without valuation type gets the one of ZPTP_301_VALTYPE (059); a missing batch is created with it.
- ZPTP_301_VALTYPE is read for the fiscal year of the posting date, most specific entry first (plant + material type, plant, material type, generic). No entry: the line is skipped (058).
- The material must be extended to and batch-managed in 8Q01. A line that cannot be transferred gets status W and the next one is processed.
- Full / Direct, the quantity and file name checks, "Force qty", "Only file items" and "Create batches with zero stock" do not apply.

### 3.7 Block "Organizational data"

| Field | Default | What to enter |
| --- | --- | --- |
| Source plant (P_WSRC) | 8P01 | Plant whose stock is moved. |
| Target plant (P_WDST) | 8Q01 | Split-valuated receiving plant; must differ from the source. |
| Material (S_MATNR) | blank | Restricts the run to some materials, in the stock and in the file. |
| Batch (S_CHARG) | blank | Restricts the run to some batches. Enter the batch as stored in SAP (with leading zeros when it has them). |
| Material type (S_MTART) | blank | Restricts the run to some material types; other materials are skipped without a message. |
| Posting date (P_BUDAT) | today | Posting date of every document. The period must be open. |
| Max. materials per run (P_MAXMT) | 9 999 999 | Processes only the first N materials (file order; option 2: stock order), 0 = no limit. Run again with the same RUN_ID to take the next N: the lines already posted under that RUN_ID are skipped. A W row (056) gives what was processed and what is left. |

The filters also narrow the "stock missing from the file" step: run the final migration without filters.

### 3.8 Which options apply where

| Option | Option 1 (types 1-3) | Option 2 (types 1-3) | Project stock (type 4) | Online | Background |
| --- | --- | --- | --- | --- | --- |
| Simulation | yes | yes | yes | **no** (hidden) | yes |
| Simulation without log | yes | yes | yes | **no** (hidden) | with Simulation |
| Run as background job | yes | yes | yes | **no** | yes |
| Full / Direct | yes | ignored | ignored | yes | yes |
| Deactivate qty check | yes | ignored | ignored | yes | yes |
| Deactivate file name check | yes | yes | ignored | yes | yes |
| Force qty to source stock | yes | ignored | ignored | yes | yes |
| Only file items in src plant | yes | ignored | ignored | yes | yes |
| Only SAP variance >= 0 | yes | yes | yes | hides and blocks | hides |
| Create batches with zero stock | yes | yes | ignored | yes | yes |
| Reprocess errors | yes | yes | yes | yes | yes |
| Max. materials per run | yes | yes | yes | yes | yes |

Refused combinations: Online with "Run as background job"; Online in a background job; "Run as background job" with a local file; "Delete all logs" with "Reprocess errors".

### 3.9 Variants

Save your settings as variants (Goto → Variants → Save as Variant), for example:

| Variant | Settings |
| --- | --- |
| SIM_UNR | Background, Simulation (without log), Full validation, option 1, type 1, server file |
| REAL_UNR | Same, Simulation unticked |
| ONLINE_UNR | Online, option 1, type 1 |
| SIM_NONSPL | Background, Simulation, option 2, type 1 |
| REAL_PRJ | Background, type 4 (no file) |

A background job scheduled in SM36 needs a variant.

## 4. Choosing the settings: typical scenarios

| Goal | Settings |
| --- | --- |
| Check the file without posting | Background, **Simulation**, Full validation (Simulation without log ticked: nothing stored; untick it to keep the simulation in the log) |
| Real migration of the file, all at once | Background, Simulation unticked, Full validation (with "Run as background job" for a large file) |
| Post only the file, nothing else | add **Only file items in src plant** |
| File quantities out of date | add **Force qty to source stock** |
| Post selected materials under control | **Online**, double-click the material, Post |
| Post only batches with enough stock | Online + **Only SAP variance >= 0** |
| Migrate non-split materials | **Non split valuation materials**, same file, Simulation first |
| Migrate blocked / QI stock | Stock type 2 or 3 with a file extracted for that type |
| Migrate project stock | Stock type 4, no file |
| Large volume in slices | **Max. materials per run** = N, same RUN_ID for each run |
| Fix the last errors | RUN_ID of the real run + **Reprocess errors**, or Online and Post the failed lines again |

## 5. Running the migration, step by step

### Step 1 — Put the file in place

1. Extract the file with the utility for the stock type, check it against 2.2.
2. For a server run, copy it to the application server (ZPTP_SPLIT_VAL_UPLD, or CG3Z in text mode) and check it in AL11.

### Step 2 — Full simulation

1. Start ZPTP_SPLIT_VAL_MIG. Execution mode: **Background**, **Simulation** ticked.
2. Run control: Full validation; leave the other checkboxes unticked.
3. Input file: choose the file. Maintenance: Run ID blank.
4. Processing option: option 1. Stock type: the one of the file. Organizational data: plants, posting date of the real run, no filters.
5. Press F8 (or tick "Run as background job" for a large file).

Every row is T (would be posted), Z, W, X or E. With "Simulation without log" ticked (default) the list is the only result: export it if you want to keep it. Untick it to store the simulation under its RUN_ID.

### Step 3 — Correct and simulate again

1. Filter on status E (and W, X), sort by Msg No.
2. Fix each cause with section 7: the file, the material master, the valuation segments, ZPTP_SLOC_MAP, the storage locations of 8Q01.
3. Repeat step 2 until no E line is left that the business has not accepted. Delete old simulation runs with "Delete run ID" if you wish.

### Step 4 — Prepare the real run

- [ ] Final simulation clean, reviewed and signed off.
- [ ] Stock of 8P01 frozen since the final simulation.
- [ ] Posting period open.
- [ ] The file is exactly the one simulated.

### Step 5 — Post for real

**All at once:** same settings as the final simulation, **Simulation unticked**, Run ID blank, F8 (or background job). Note the RUN_ID.

**Line by line:** Execution mode **Online**, same settings otherwise, F8. In the list, tick lines (or double-click a material), press **Post**, confirm. Repeat until every line you want is green.

Each S row has its material document; batches created in 8Q01 are in ZPTP_BATCH_EXT.

### Step 6 — Reprocess the remaining errors

1. Fix the cause of each E line.
2. Enter the RUN_ID of the real run, tick **Reprocess errors**, keep the other settings, Simulation unticked (tick it first to check, if you wish).
3. Execute: only the E lines of the previous sequence are processed, as a new sequence.

### Step 7 — The other parts of the plant

- Option 2 (non-split materials) with the same file: simulation, then real run.
- Stock types 2 and 3 with their own files, project stock (type 4) without file: simulation, then real run each.

## 6. Reading the result

The list has one row per line, movement and issuing storage location. The same rows are saved in ZPTP_MOV_EXEC (SE16 by RUN_ID), except the ready rows of Online mode.

### 6.1 Statuses

| Status | Meaning | Posted | What to do |
| --- | --- | --- | --- |
| S | Posted; material document filled | yes | Nothing; check a sample in MB51. |
| T | Simulation: would be posted (Mat.Doc = SIMULATED) | no | Ready for the real run. |
| R | Online: ready to post | not yet | Tick and Post. |
| Z | Zero quantity, no movement | no | Nothing, unless the quantity is wrong. |
| W | Warning: run information (054, 056), last movement failed (types 2 / 3), project stock line skipped, QI held by inspection lots (055) | depends | Read the message. |
| E | Error: stopped at the first failed check | no | Fix the cause (section 7), then reprocess or Post again. |
| X | Not processed: stock not in the file with nothing to move (011), file line not in 8P01 with "Only file items" (061) | no | Review; nothing to do if expected. |

A posted line keeps its success message ("Material document …"). Warnings found during preparation (010 added from SAP stock, 057 already transferred, 060 quantity forced) are shown only on rows that were not posted.

### 6.2 Columns

| Column | Content |
| --- | --- |
| Line | Online only: number of the line, the list stays in file order |
| RUN_ID, Seq, Mode, Simulation | Run identification |
| Status, Msg Type, Msg No, Message | Result and explanation (the message class is hidden; show it with the layout button) |
| Material, Batch, Val.Type, WBS element | The line (WBS element for project stock only). Batch = the batch as it exists in SAP |
| File batch, Punct. swapped | The batch as written in the file, and X when it was found only with "," and "." swapped |
| BatchMgd | X on every row of a batch-managed material |
| Src Plant, Src SLoc / Dst Plant, Dst SLoc | Where the stock is in 8P01 / where it goes in 8Q01 (from ZPTP_SLOC_MAP) |
| Qty Posted, UoM | Quantity of this row: the part of the line issued from that storage location. On a failed row, the quantity attempted; on a ready row, the quantity that would be posted |
| File Qty | Quantity of the file line (before forcing) |
| SAP Stock | Stock of the type moved in 8P01 for the material + batch, all storage locations, at the start of the run |
| File Variance | File total − SAP Stock for the material + batch (the quantity check); 0 when the check does not run |
| SAP Variance | SAP stock − quantity the run transfers for the material + batch (file, forced or whole-stock quantities; rejected lines excluded). 0 = the run takes the whole stock; positive = stock that stays in 8P01; negative = more to transfer than the stock: red cell and a warning at the end of the message, check MMBE and the file. Green cell when 0 or more. List only |
| Mvt type, Mat.Doc, Year | Movement (301, 343, 344, 321, 322) and its document |
| Batch normalised | X when the batch value of the file was reduced to blank (012) |

### 6.3 Order and colours

- Background: grouped by status (T, S, E, W, Z, X, R), separator line between statuses, then by message, material and batch. Online: file order.
- Whole row red = error, green = posted or simulated, yellow = warning. Rows without a result (ready rows in Online) alternate white / light blue at each change of material.
- Useful ALV functions: filter on Status, sort by Msg No, subtotal Qty Posted per material, export to a spreadsheet for the business review.

## 7. Messages and how to fix them

### 7.1 On the selection screen

| Message | Fix |
| --- | --- |
| Source / Target plant … does not exist (T001W) | Correct the plant. |
| Source and target plant must be different | Enter 8P01 → 8Q01. |
| Posting date is required | Fill the posting date. |
| No storage location mapping from plant … to plant … in table ZPTP_SLOC_MAP | Fill ZPTP_SLOC_MAP (SM30) for this plant pair. |
| A field separator is required | Enter the separator (`;`). |
| Please specify the input file path | Fill the file path (not needed for project stock). |
| Input file not found or not readable on the application server | Check the path and its case in AL11, and your access. |
| Local input file not found | Check the path, or use F4. |
| File name … does not match the stock type | Use the file extracted for this stock type, or choose the right stock type; tick "Deactivate file name check" only if you are sure. |
| A background job needs the file on the application server | Copy the file with ZPTP_SPLIT_VAL_UPLD and choose Application server. |
| Online mode runs in dialog | Untick "Run as background job", or choose Background. |
| The maximum number of materials cannot be negative | Enter 0 (no limit) or a positive number. |
| Delete all logs cannot be combined with Reprocess errors | Untick one of them. |
| Reprocess-errors requires an existing RUN_ID / RUN_ID … does not exist | Enter the RUN_ID exactly as in the log. |
| RUN_ID is required for the delete/maintenance option | Enter the RUN_ID to delete. |
| No usable line in the input file | Every line was rejected: check separator, column order and encoding; the rejected lines are in the log. |
| No error lines to reprocess for this RUN_ID | Nothing to do. |

### 7.2 On the result rows

| No. | Status | Meaning | How to fix |
| --- | --- | --- | --- |
| 002 | Z | Zero quantity, no movement | Nothing, unless the quantity is wrong. |
| 003 | E | Valuation type missing in 8Q01 | Create the valuation segment in 8Q01 (MM02, accounting view) or correct BWTAR in the file. |
| 004 | E | File quantity differs from SAP stock | Compare File Qty, SAP Stock, File Variance; correct the file, or use "Force qty to source stock" / "Deactivate qty check". |
| 005 | E | Not enough stock left in the storage locations | Other lines of the same batch used the stock first; check the quantities in the file. |
| 006 | E | No stock of the type moved in 8P01 | Check MMBE: the stock may be of another type or already moved. A blank batch on a batch-managed material also gives 006. |
| 007 / 008 | E | Quantity not numeric / negative | Correct the quantity. |
| 009 | E | Layout error, mandatory field blank, invalid material | Correct the line and the separator. |
| 010 | W / E | Batch not in the file, added with the SAP stock (posted). E: split-valuated in 8Q01 and no valuation type found | E: add the batch to the file with its valuation type. W: nothing, if the business agrees; otherwise use "Only file items in src plant". |
| 011 | X | Stock not in the file, nothing of the type moved | Nothing. |
| 012 | W | Batch column reduced to blank (placeholder value) | Use NO_BATCH or a blank. |
| 013 | E | NO_BATCH on a batch-managed material | Put the real batch numbers in the file. |
| 014 | E | Material not extended to one of the plants | Extend the material (MM01 / MM02). |
| 015 | E | NO_BATCH but batch stock exists in 8P01 | Use the batch numbers from MMBE. |
| 016 | E | Same batch with several valuation types | One batch, one valuation type: correct the file. |
| 017 / 018 | E | Unknown unit / unit differs from the base unit | Use the base unit, or leave the unit blank; save the file as UTF-8. |
| 019 | E | Batch exists in 8Q01 with another valuation type | Check the batch in MSC3N; correct the file or the batch. |
| 020 | E | Source batch cannot be read in 8P01 | Check the batch in MSC3N. |
| 022 | E | Update failed after commit, document not posted | Check SM13, fix, reprocess. |
| 023 | E | Mapped target storage location missing in 8Q01 | Correct ZPTP_SLOC_MAP or create the storage location in 8Q01. |
| 024 | E | No ZPTP_SLOC_MAP entry for the storage location (Src SLoc) | Add the entry in SM30, then reprocess. |
| 025 | E | Option 2: material split-valuated in 8Q01 | Put the material in the file and use option 1. |
| 026 | E / W | Batch management differs between 8P01 and 8Q01 | Align the batch management indicator. |
| 054 | W | Run parameters (first row of every run) | Nothing: records the options used. |
| 055 | W | QI stock held by inspection lots stays in 8P01 | Close the lots (QA11) if that stock must move, then run again. |
| 056 | W | Max. materials: processed and left | Run again with the same RUN_ID for the next materials. |
| 057 | W | Batch already transferred in an earlier run | Check that it is not a duplicate before posting. |
| 058 | W | Project stock: no ZPTP_301_VALTYPE entry | Maintain ZPTP_301_VALTYPE for the plant / material type and fiscal year. |
| 059 | — | Project stock: valuation type set on the batch in 8Q01 | Nothing (in ZPTP_BATCH_EXT). |
| 060 | W | Quantity forced to the stock of 8P01 | Nothing: expected with "Force qty"; check large differences. |
| 062 | E | Batch with "," or "." not found, neither as written nor with the punctuation swapped (both values shown) | Check the batch in MSC3N and correct the file. |
| 063 | W | Both forms of a batch with "," or "." exist (e.g. 24.105 and 24,105); the one as written was used | Check with the business whether one of them is a duplicate. |
| 061 | X | File line not in 8P01 (material not extended or batch missing) | Nothing if expected; otherwise check MM03 / MSC3N, and the batch number (leading zeros). |
| other | E | Message of BAPI_GOODSMVT_CREATE / BAPI_BATCH_CREATE (e.g. M7) | Read it in SE91: closed period, locked material, missing storage location data, authorization. |

### 7.3 Other problems

| Symptom | Cause and fix |
| --- | --- |
| Every unit rejected (017) | File uploaded in binary mode: upload it again in text mode. |
| First data line missing | No header and the first quantity is not numeric: add a header line. |
| Local file run fails in background | Use Application server. |
| Dialog run stops with a time-out | Use "Run as background job", or "Max. materials per run". |
| Simulation checkbox not visible | Online mode is selected: Simulation does not apply there. |
| A simulation run cannot be found in ZPTP_MOV_EXEC | "Simulation without log" was ticked (default): the result was only in the list. Untick it to log simulations. |
| Many lines in 006 although stock exists | Wrong stock type, or filters (material type, batch) too narrow. |

## 8. After the real run

### 8.1 Checks

- [ ] No line left in status E for the RUN_ID of the real run.
- [ ] SAP Variance 0 for every migrated material + batch, or the remaining stock explained.
- [ ] Stock of the migrated type in 8P01 is zero for the migrated materials (MMBE / MB52).
- [ ] Stock in 8Q01 per material, batch, valuation type and storage location matches the file (MB52).
- [ ] The documents of the run are in MB51 (one 301 per S line; 343/344 or 321/322 for types 2 and 3).
- [ ] Batches created in 8Q01 have the valuation type and dates of the source batch (MSC3N, ZPTP_BATCH_EXT).
- [ ] Stock values per valuation type in 8Q01 agreed with Finance.
- [ ] W and X lines reviewed and signed off.

### 8.2 Good practice

- Never post before a clean simulation of the same file, the same day.
- Keep the input file of every real run with its RUN_ID.
- Run the final migration without filters.
- Use Direct transfer, "Deactivate qty check" and "Force qty" only when agreed.
- Never delete a run with postings: ZPTP_MOV_EXEC is the audit trail.
- To reverse a posting, cancel the document in MIGO / MBST, then correct and post the line again.
- Batch classification is not copied: plan it separately if needed.
