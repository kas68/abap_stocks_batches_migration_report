# abap_stocks_batches_migration_report

HBM – Split Valuation migration: ABAP report **`ZPTP_SPLIT_VAL_MIG`**.

Transfers unrestricted stock (batch-managed and non-batch materials) from plant **8P01** to the
new split-valuated plant **8Q01** with movement type **301**, driven by the HBM Valuation Type
Input File. Each item's receiving storage location comes from the mapping table
`ZPTP_SLOC_MAP`. The program runs full validation,
creates the target batches, has a simulation mode (BAPI `TESTRUN`), restart by `RUN_ID`, and
logs every record in `ZPTP_MOV_EXEC` (batch extensions in `ZPTP_BATCH_EXT`).

| File | Content |
|---|---|
| [`ZPTP_SPLIT_VAL_MIG.abap`](ZPTP_SPLIT_VAL_MIG.abap) | Executable report (SE38) |
| [`ZPTP_SPLIT_VAL_DDIC.txt`](ZPTP_SPLIT_VAL_DDIC.txt) | SE11 objects (`ZPTP_MOV_EXEC`, `ZPTP_BATCH_EXT`, `ZPTP_SLOC_MAP`, data elements) and message class `ZPTP_SPLIT_VAL` |
| [`ZPTP_SPLIT_VAL_README.md`](ZPTP_SPLIT_VAL_README.md) | Technical documentation: processing logic, input file, modes, deployment, naming, open points |
| [`ZPTP_SPLIT_VAL_FUNCTIONAL_SPEC.md`](ZPTP_SPLIT_VAL_FUNCTIONAL_SPEC.md) | Functional specification and user guide: processing, selection-screen parameters, input file format, results |
| [`ZPTP_SPLIT_VAL_SPEC_FONCTIONNELLE.md`](ZPTP_SPLIT_VAL_SPEC_FONCTIONNELLE.md) | The same functional specification and user guide, in French |
| [`ZPTP_SPLIT_VAL_USER_GUIDE.md`](ZPTP_SPLIT_VAL_USER_GUIDE.md) | Step-by-step user guide for running the report: preparation, selection screen, simulation and real run, results, message fixes, post-run checks |
| [`HIGH_LEVEL_OVERVIEW.md`](HIGH_LEVEL_OVERVIEW.md) | Non-technical overview: why the program exists and what it does |
| [`ZPTP_SPLIT_VAL_MIG_UTILITY.abap`](ZPTP_SPLIT_VAL_MIG_UTILITY.abap) | Transaction `ZPTP_SPLIT_VAL_UTIL`. Builds the CSV input file from SAP data |
| [`ZPTP_SPLIT_VAL_MIG_UPLOAD.abap`](ZPTP_SPLIT_VAL_MIG_UPLOAD.abap) | Transaction `ZPTP_SPLIT_VAL_UPLD`. Copies the input file from the PC to the application server (needed to run the migration as a background job) |
| [`ZPTP_SPLIT_VAL_BATCH_COPY.abap`](ZPTP_SPLIT_VAL_BATCH_COPY.abap) | Transaction `ZPTP_SPLIT_VAL_BCPY`. Reads an Excel file (material; batch; valuation type) and copies the batch data of plant 8P01 to plant 8Q01, enriched with the valuation type |
| *(SAP)* Area menu `ZPTP_SVAL_MENU` | Menu of the transactions `ZPTP_SPLIT_VAL_MIG`, `ZPTP_SPLIT_VAL_BCPY`, `ZPTP_SPLIT_VAL_UPLD`, `ZPTP_SPLIT_VAL_UTIL` (and of the reservation transactions of another development) |
| `SAP ABAP Development Standard and Namimg Conventions.docx` | Sysmex D-Project ABAP Development Standards & Naming Conventions v1.2, which the object names follow |

**Current version:** program v1.1. v1.1 adds a detailed log (one row per movement with its own document, a run-parameter row, and the QI stock left in inspection lots). v1.0 adds the transfer of blocked stock (343 / 301 / 344) and of quality-inspection stock without inspection lot (321 / 301 / 322), selected on the screen. v0.9 adds the stock scope of the quantity check (unrestricted / blocked / quality inspection, in combinations) and the option to deactivate that check. v0.8 adds the checkbox `P_ZBAT` (batches with zero stock),
robust handling of units containing μ / ρ, UTF-8 decoding of a local input file, and a coloured,
re-sorted ALV list. v0.7 added the processing option (1 split valuation materials / 2 non split
valuation materials) and removed the outer screen frame (text symbol T01). v0.6 reads the receiving storage location of each item
from the new table `ZPTP_SLOC_MAP` instead of reusing the issuing code. v0.5 renamed the objects to the customer naming conventions (Work Stream ID **PTP**) and changed
nothing in the processing. The report was `ZHBM_SPLIT_VAL_PH1`, the log tables `ZLOT_*`, and
the message class `ZHBM`.

**Status:** v0.5 activated in the SAP sandbox; v0.6 not yet activated (create `ZPTP_SLOC_MAP`
and message 024 first). The errors found at first activation are fixed (see
*Fixes from the first activation* in the technical README). Not yet run end to end: see *To
verify in the sandbox* before the first real run.
