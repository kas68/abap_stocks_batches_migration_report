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
| `SAP ABAP Development Standard and Namimg Conventions.docx` | Sysmex D-Project ABAP Development Standards & Naming Conventions v1.2, which the object names follow |

**Current version:** program v0.6. v0.6 reads the receiving storage location of each item
from the new table `ZPTP_SLOC_MAP` instead of reusing the issuing code. v0.5 renamed the objects to the customer naming conventions (Work Stream ID **PTP**) and changed
nothing in the processing. The report was `ZHBM_SPLIT_VAL_PH1`, the log tables `ZLOT_*`, and
the message class `ZHBM`.

**Status:** v0.5 activated in the SAP sandbox; v0.6 not yet activated (create `ZPTP_SLOC_MAP`
and message 024 first). The errors found at first activation are fixed (see
*Fixes from the first activation* in the technical README). Not yet run end to end: see *To
verify in the sandbox* before the first real run.
