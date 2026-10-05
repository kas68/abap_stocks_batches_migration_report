# ZPTP_SPLIT_VAL_MIG — User Guide

2026-10-02 · program v0.6

## 1. What the report does

ZPTP_SPLIT_VAL_MIG moves all unrestricted stock from plant 8P01 to the split-valuated plant 8Q01 with movement type 301, using the HBM Valuation Type Input File to assign a valuation type to each material and batch. Always run it in simulation first, fix what it reports, then run it for real.

For each line of the input file, the report:

1. reads the unrestricted stock of the material (and batch) in 8P01, per storage location;
2. checks the line: unit, quantity, valuation segment in 8Q01, storage locations in 8Q01, batch consistency;
3. creates the batch in 8Q01 when it is missing, copying the source batch attributes and setting the target valuation type;
4. posts one 301 material document per file line, one item per issuing storage location, received in the 8Q01 storage location given by the mapping table ZPTP_SLOC_MAP;
5. writes one log row per item in table ZPTP_MOV_EXEC and shows the result in an ALV list.

The report handles batch-managed and non-batch-managed materials. It does not move quality-inspection, blocked or special stock, and it does not copy batch classification.

| Item | Value |
| --- | --- |
| Program | ZPTP_SPLIT_VAL_MIG (version 0.5) |
| Screen title | STOCKS & BATCHES MIGRATION PROGRAM |
| Start from | SE38 or SA38 (no transaction code yet) |
| Movement type | 301, one-step plant-to-plant transfer |
| Default plants | 8P01 (source) to 8Q01 (target) |
| Log tables | ZPTP_MOV_EXEC (movements), ZPTP_BATCH_EXT (batches) |
| Storage location mapping | ZPTP_SLOC_MAP (maintained with SM30) |
| Message class | ZPTP_SPLIT_VAL |

## 2. Before you run it

Check these points before the first simulation; each one that is missing shows up later as a blocked line.

### 2.1 Target plant set-up (8Q01)

- [ ] Plant 8Q01 exists (T001W) and is not the same as the source plant.
- [ ] Table ZPTP_SLOC_MAP (SM30) has one entry per storage location of 8P01 that holds stock: source plant 8P01, source storage location, target plant 8Q01, target storage location. A missing entry blocks the line with message 024. Several source storage locations may point to the same target one.
- [ ] Every target storage location in ZPTP_SLOC_MAP exists in 8Q01 (T001L). A missing one blocks the line with message 023.
- [ ] Every material in the file is extended to 8Q01, with a valuation segment for each valuation type used in the file (MBEW, valuation area = plant). A missing segment blocks the line with message 003 in Full Validation mode.
- [ ] Batch management in 8Q01 matches 8P01 for each material.

### 2.2 The input file

- [ ] One line per material / batch / valuation type, five columns in this order: MATNR; CHARG; BWTAR; QUANTITY; UOM.
- [ ] Quantities in the material's base unit. For each material and batch, the file total equals the unrestricted stock in 8P01 (all storage locations), to three decimals.
- [ ] A batch carries one valuation type only.
- [ ] Non-batch materials: batch column blank or NO_BATCH.
- [ ] No separator inside a value, no thousands separator, no BOM. Decimals with point or comma.
- [ ] For a server file: uploaded in text mode (for example with CG3Z, transfer format ASC), so no stray carriage return ends up in the unit.

Example:

```csv
MATNR;CHARG;BWTAR;QUANTITY;UOM
100234;0000004711;VT01;150,000;KG
100234;0000004712;VT02;80,000;KG
200987;NO_BATCH;VT01;1250,000;PC
300555;;VT02;0,000;L
```

The header line is optional. The storage location, plants, movement type and posting date are not in the file: they come from SAP stock and the selection screen.

### 2.3 Authorizations

| Task | Authorization |
| --- | --- |
| Start the report | SE38 or SA38 |
| Post the 301 movements | Standard goods movement checks of BAPI_GOODSMVT_CREATE (plants 8P01 and 8Q01, movement type 301) |
| Create batches in 8Q01 | Standard checks of BAPI_BATCH_CREATE |
| Read a server file | Read access to the file path (S_DATASET) |
| Delete a RUN_ID from the log | S_TABU_NAM, activity 02, table ZPTP_MOV_EXEC |

### 2.4 Timing

- Agree a freeze: no goods movements in 8P01 between the final simulation and the real run, or the quantity check fails with message 004.
- Check that the posting period for the posting date is open in both plants (MMPV / OB52).

## 3. The selection screen

The screen has four blocks. Its checks run only when you execute (F8, background job or print), not while you fill it in, so switching a radio button never raises an error.

### 3.1 Organizational data

| Field | Default | Required | What to enter |
| --- | --- | --- | --- |
| Source plant (P_WSRC) | 8P01 | yes | Plant whose unrestricted stock is moved. Must exist and differ from the target plant. |
| Target plant (P_WDST) | 8Q01 | yes | Split-valuated receiving plant. Segments, batches and storage locations are checked here. |
| Material (S_MATNR) | blank | no | Restricts the run to some materials, in the stock and in the file. |
| Batch (S_CHARG) | blank | no | Restricts the run to some batches. |
| Material type (S_MTART) | blank | no | Restricts the run to some material types. Excluded materials are skipped without a message. |
| Posting date (P_BUDAT) | today | yes | Posting date of every 301 document. The period must be open. |

Any of the three filters also narrows the "SAP stock missing from the file" check. Use them for tests or targeted runs; run the final migration without filters.

### 3.2 Input file

| Field | Default | Required | What to enter |
| --- | --- | --- | --- |
| Application server (P_SRV) | selected | one of the two | File on the SAP application server. The only choice that works in a background job. |
| Local file (P_LOC) | — | one of the two | File on your PC, uploaded through SAP GUI. Dialog runs only. |
| Input file path (P_FILE) | blank | yes | Full path of the file. Press F4 to browse the server directory or your PC, depending on the choice above. The path is case-sensitive on the server. |
| Field separator (P_SEP) | ; | yes | Column separator used in the file. |

### 3.3 Run control

| Field | Default | Required | What to enter |
| --- | --- | --- | --- |
| Run ID, blank=new (P_RUNID) | blank | no | Blank creates a new RUN_ID, HBM + date + time (for example HBM20261002143015). Enter an existing RUN_ID to add the run to it as the next sequence (001, 002, ...). Required with Reprocess errors and Delete run ID. |
| Reprocess errors (P_REPRC) | off | no | Reprocesses only the lines in status E of the previous sequence of the RUN_ID. |
| Full validation (P_FULL) | selected | one of the two | Standard mode: every check applies. Use it for the migration. |
| Direct transfer (P_DIR) | — | one of the two | Skips the valuation segment check, the quantity check and the "SAP stock missing from the file" check. Only for materials whose split valuation is not yet active in the target plant, and only when agreed. |
| Simulation (P_TEST) | on | no | On: everything is checked, nothing is posted and no batch is created. Off: real posting. |
| ALV status (S_STAT) | blank | no | Shows only the selected statuses in the result list. F4 lists the values with their meaning and lets you tick several; the Multiple Selection button accepts ranges and exclusions. Blank shows every status. Only the display is filtered: all lines are still processed and logged. |

### 3.4 Maintenance

| Field | Default | Required | What to enter |
| --- | --- | --- | --- |
| Delete run ID (P_DEL) | off | no | With a RUN_ID, deletes that run's rows from both log tables after a confirmation. Nothing else runs. Refused when the run has real postings. |
| Delete all logs before the run (P_CLR) | off | no | Empties both log tables completely before the migration starts, after a confirmation (no popup in a background job). The log of runs that posted documents is deleted too, so use it only when the history is no longer needed. Needs the table authorization. Cannot be used with Reprocess errors. |

Save your settings as a variant (Goto > Variants > Save as Variant), for example one variant for simulation and one for the real run. A background job needs a variant.

## 4. Running the migration, step by step

The migration is a cycle: simulate, correct, simulate again until clean, post once for real, then reprocess the few lines left in error under the same RUN_ID.

### Step 1 — Put the file in place

1. Get the HBM Valuation Type Input File and check it against section 2.2.
2. For a server run, upload it to the application server in text mode (CG3Z, or the tool your Basis team provides) and note the full path. Check it with AL11.
3. For a dialog test run, you can keep the file on your PC and use Local file instead.

### Step 2 — Run a full simulation

1. Start SE38 (or SA38), enter ZPTP_SPLIT_VAL_MIG and press F8.
2. Keep plants 8P01 and 8Q01, leave Receiving SLoc and all filters blank.
3. Set the posting date you will use for the real run.
4. Choose Application server (or Local file), enter the path with F4 and keep the separator `;`.
5. Leave Run ID blank, Full validation selected and Simulation ticked.
6. Press F8.

The report shows the ALV result list (section 5). Every line is either T (would be posted), Z (zero quantity), W, I, X or E. Note the RUN_ID shown in the RUN_ID column. For a large file, run the simulation in background instead (step 6) and read the result from the spool.

### Step 3 — Correct and simulate again

1. Filter the list on status E, I and X and sort by message number.
2. Correct the cause of each message with section 6: the file, the material master, the valuation segments, the storage location mapping (ZPTP_SLOC_MAP) or the storage locations of 8Q01.
3. Re-upload the corrected file and repeat step 2 with Run ID blank, until no E, I or X line is left that the business has not accepted.

Optionally delete old simulation runs from the log with Delete run ID (step 8).

### Step 4 — Prepare the real run

- [ ] Final simulation is clean and the result has been reviewed and signed off.
- [ ] Stock in 8P01 is frozen: no goods movements since the final simulation.
- [ ] Posting period is open for the posting date.
- [ ] The file on the server is exactly the one simulated.

### Step 5 — Post for real

1. Start the report with the same values as the final simulation.
2. Leave Run ID blank, so the real postings get their own RUN_ID.
3. Untick Simulation.
4. Execute: F8 for a dialog run, or a background job (step 6) for a large file.
5. Write down the RUN_ID of this run. You need it for reprocessing and for the audit trail.

Each line in status S has a material document number. Batches created in 8Q01 are logged in ZPTP_BATCH_EXT.

### Step 6 — Running in background

Use a background job for large volumes: a dialog run can hit the time-out.

1. Fill the screen with Application server (Local file does not work in background) and save it as a variant.
2. In SE38, choose Program > Execute in Background, or schedule the program with SM36 using that variant.
3. Follow the job in SM37. When it is finished, open its spool: it holds the run header (RUN_ID, sequence, mode, plants, posting date) and the result list.

The posting date is checked again at the start of the job.

### Step 7 — Reprocess the remaining errors

After the real run, some lines may still be in status E, for example a locked material or a missing segment.

1. Correct the cause of each error.
2. Start the report with the same file, enter the RUN_ID of the real run, tick Reprocess errors, keep Full validation and untick Simulation. You can tick Simulation first to check the correction.
3. Execute. Only the E lines of the previous sequence of that RUN_ID are processed, as a new sequence (002, 003, ...).
4. Repeat until no E line is left.

Reprocessing takes the E lines of the previous sequence only. If you run a simulation sequence in between, the next reprocessing starts from that simulation sequence's E lines, which are the same lines when nothing was posted.

Lines in status I cannot be reprocessed: they are not in the file. Add them to the file and start a new full run (Run ID blank, no Reprocess errors).

### Step 8 — Delete a run from the log (optional)

1. Enter the RUN_ID, tick Delete run ID and execute.
2. Confirm the popup. Only the log rows of ZPTP_MOV_EXEC and ZPTP_BATCH_EXT are deleted; no stock moves.

Deletion is refused when the run holds real postings (status S, not simulated). Use it only to clean up simulation runs.

## 5. Reading the result

The ALV list has one row per file line and per issuing storage location; the Status and Message columns tell you what happened. The same rows are saved in ZPTP_MOV_EXEC, so you can read any run again later in SE16 by RUN_ID.

### 5.1 Statuses

| Status | Meaning | Posted | What to do |
| --- | --- | --- | --- |
| S | Success: 301 posted, material document filled | yes | Nothing. Check a sample in MB51. |
| T | Simulation: the line would be posted. Material document shows SIMULATED. | no | Ready for the real run. |
| Z | Quantity zero in the file | no | Nothing, unless the quantity is wrong. |
| W | Warning, for example batch value reduced to blank (012) | depends | Read the message; correct the file if the value was a typo. |
| E | Error: the line was stopped at the first failed check | no | Correct the cause (section 6) and rerun or reprocess. |
| I | Stock in 8P01 missing from the file, and a valuation segment exists in 8Q01 | no | Add the material/batch to the file, then run a full run. |
| X | Stock in 8P01 missing from the file, no segment in 8Q01 | no | Confirm it is meant to stay in 8P01; otherwise add it to the file. |

### 5.2 Columns

| Column | Content |
| --- | --- |
| Status, Message, Msg Type, Msg Class, Msg No | Result of the line and the message that explains it |
| Material, Batch, BatchMgd, Val.Type | The file line; BatchMgd = X for a batch-managed material |
| Src Plant, Src SLoc | Issuing plant and storage location, where the stock currently is (from SAP stock). A line rejected before the allocation (002 to 005) shows one row per storage location holding stock |
| Dst Plant, Dst SLoc | Receiving plant and storage location, where the stock will be moved (from ZPTP_SLOC_MAP; on a 023 error the missing target; blank when the source location has no mapping or the line has no stock) |
| Qty Posted, UoM | Quantity of this item, in the base unit |
| File Qty, SAP Stock, Variance | File total, unrestricted stock in 8P01 and the difference, per material and batch |
| Mat.Doc, Year | 301 material document, or SIMULATED |
| RUN_ID, Seq, Mode, Simulation | Run identification: sequence, FULL or DIRECT mode, X for a simulation |
| Batch normalised | X when the batch value of the file was reduced to blank (see message 012) |

The rows are grouped by status: T and S first, then E, W, Z, I and X. Inside a status the order of the file is kept.

Useful ALV functions: filter on Status, sort by Msg No, subtotal Qty Posted by material, and export to a spreadsheet (List > Export) for the business review.

### 5.3 Logs to keep

| Table | One row per | Key |
| --- | --- | --- |
| ZPTP_MOV_EXEC | Processed line and issuing storage location | RUN_ID, RUN_SEQ, POSNR |
| ZPTP_BATCH_EXT | Batch handled in 8Q01: created, already there, simulated or failed | RUN_ID, RUN_SEQ, MATNR, CHARG, WERKS_DST |

Each material document is committed together with its log rows, so every posted document has a log row. If a row reports that some log rows were not written (duplicate key), tell the development team.

## 6. Messages and how to fix them

Every blocked line carries a message of class ZPTP_SPLIT_VAL, or the message of the SAP BAPI that refused it. A line stops at its first failed check, so a fixed line can show a new message on the next simulation.

### 6.1 Messages on the selection screen

| Message | Fix |
| --- | --- |
| Source/Target plant ... does not exist (T001W) | Correct the plant code. |
| Source and target plant must be different | Enter 8P01 as source and 8Q01 as target. |
| Posting date is required | Fill Posting date. |
| Storage location ... does not exist in plant ... (T001L) | Clear Receiving SLoc; it is not needed. |
| No storage location mapping from plant ... to plant ... in table ZPTP_SLOC_MAP | Fill ZPTP_SLOC_MAP (SM30) for this plant pair, or check the plants. |
| A field separator is required | Enter the separator used in the file (`;`). |
| Please specify the input file path | Fill Input file path. |
| Input file not found or not readable on the application server | Check the path and its case in AL11, and that you have read access. |
| Local input file not found | Check the path on your PC, or use F4. |
| Reprocess-errors requires an existing RUN_ID / RUN_ID ... does not exist in ZPTP_MOV_EXEC | Enter the RUN_ID of the run to reprocess, exactly as in the log. |
| RUN_ID is required for the delete/maintenance option | Enter the RUN_ID to delete. |
| No usable line in the input file | Every line was rejected. Check the separator, the column order and the encoding; the rejected lines are in the log. |
| No error lines to reprocess for this RUN_ID | The previous sequence has no E line; nothing to do. |

### 6.2 Messages on the result lines

| No. | Status | Meaning | How to fix |
| --- | --- | --- | --- |
| 002 | Z | Zero quantity, no movement | Nothing, unless the quantity is wrong. |
| 003 | E | Valuation type missing in 8Q01 | Create the valuation segment for that type in 8Q01 (MM02, accounting view), or correct BWTAR in the file. |
| 004 | E | File quantity differs from SAP stock | Compare File Qty, SAP Stock and Variance. Correct the file so that the total per material + batch equals the unrestricted stock in 8P01 (MMBE). Stock may have moved since the extract. |
| 005 | E | Not enough stock left in the issuing storage locations | Other lines of the same material/batch used the stock first. Check the quantities per valuation type in the file. |
| 006 | E | No unrestricted stock in 8P01 | Check MMBE: stock may be blocked, in QI, or already moved. A blank batch on a batch-managed material also gives 006: fill the batch. |
| 007 | E | Quantity not numeric | Correct the quantity (no thousands separator, no text). |
| 008 | E | Negative quantity | Correct the quantity. |
| 009 | E | Layout error: fewer than 5 columns, material or valuation type blank, or invalid material number | Correct the line and check the separator. |
| 010 | I | Stock in 8P01 not in the file, segment exists in 8Q01 | Add the material/batch to the file with its valuation type, then run a full run. |
| 011 | X | Stock in 8P01 not in the file, no segment in 8Q01 | Confirm with the business that it stays in 8P01, or add it. |
| 012 | W | Batch column reduced to blank | Expected for placeholders (N/A, NONE, -). Use NO_BATCH or a blank instead. |
| 013 | E | Material declared NO_BATCH but batch-managed in 8P01 or 8Q01 | Put the real batch numbers in the file, or correct the batch indicator of the material. |
| 014 | E | Material not extended to one of the plants | Extend the material to 8P01 or 8Q01 (MM01/MM02). |
| 015 | E | Declared NO_BATCH but batch stock exists in 8P01 | Use the batch numbers from MMBE in the file. |
| 016 | E | Same batch with several valuation types | One batch, one valuation type: correct the file, or agree new batch numbers with the business. |
| 017 | E | Unknown unit of measure | Use a valid unit (CUNIT), or leave the unit blank to take the base unit. |
| 018 | E | Unit differs from the base unit | Convert the quantity into the base unit and use that unit, or leave the unit blank. |
| 019 | E | Batch already exists in 8Q01 with another valuation type | Check the batch in MSC3N; correct the file or the batch. |
| 020 | E | Source batch cannot be read in 8P01 | Check the batch in MSC3N for 8P01. |
| 022 | E | Update failed after commit, document not posted | Check SM13 for the failed update, correct, then reprocess. |
| 023 | E | Mapped target storage location missing in 8Q01 | Correct the target storage location in ZPTP_SLOC_MAP, or create it in 8Q01 (OX09, MM customizing team). |
| 024 | E | No entry in ZPTP_SLOC_MAP for the issuing storage location (shown in Src SLoc) | Add the entry 8P01 / storage location / 8Q01 / target storage location with SM30, then reprocess. |
| other | E | Message from BAPI_GOODSMVT_CREATE or BAPI_BATCH_CREATE (for example M7, 12) | Read Msg Class and Msg No in SE91; typical causes are a closed period, a locked material or a missing authorization. |

### 6.3 Other problems

| Symptom | Cause and fix |
| --- | --- |
| Every unit is rejected (017) | The file was uploaded in binary mode: a carriage return ends up in the unit. Upload it again in text mode. |
| First data line is missing from the result | The file has no header and its first quantity is not numeric, so line 1 was taken as a header. Add a header line. |
| Local file run fails in background | Local file needs SAP GUI. Use Application server. |
| Dialog run stops with a time-out | Run it in background (section 4, step 6). |
| Many materials end in 006 although stock exists | Check the material-type and batch filters, and that the stock is unrestricted, not in QI or blocked. |

## 7. After the real run

The migration is complete when 8P01 holds no unrestricted stock that was meant to move and every S line is found in 8Q01 with the right valuation type.

### 7.1 Checks

- [ ] No line left in status E for the RUN_ID of the real run (SE16 on ZPTP_MOV_EXEC, last sequence).
- [ ] Unrestricted stock in 8P01 is zero for the migrated materials (MMBE or MB52).
- [ ] Stock in 8Q01 matches the file, per material, batch, valuation type and storage location (MMBE, MB52).
- [ ] The 301 documents of the run are in MB51 (movement type 301, plant 8P01, posting date of the run), one per S line.
- [ ] Batches created in 8Q01 have the valuation type and dates of the source batch (MSC3N; ZPTP_BATCH_EXT for the list).
- [ ] Stock values in 8Q01 per valuation type look right (MB5L or the valuation report agreed with Finance).
- [ ] Lines in status I and X have been reviewed and signed off by the business.

### 7.2 Good practice

- Never run the real posting before a clean simulation on the same file and the same day.
- Keep the input file of every real run, together with its RUN_ID.
- Run the final migration without material, batch or material-type filters, so the "stock missing from the file" check covers the whole plant.
- Use Direct transfer only for materials agreed in advance; it skips the quantity check.
- Do not delete a run that has postings: the program refuses it, because ZPTP_MOV_EXEC is the audit trail.
- Batch classification is not copied; if the business needs it in 8Q01, plan it as a separate step.
- If you need to reverse a posting, cancel the 301 document in MIGO or MBST, then correct and rerun that line.
