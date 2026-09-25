# abap_stocks_batches_migration_report

HBM – Split Valuation migration, Phase 1: ABAP report **`ZHBM_SPLIT_VAL_PH1`**.

Transfers unrestricted stock (batch-managed and non-batch materials) from plant **8P01** to the
new split-valuated plant **8Q01** with movement type **301**, driven by the HBM Valuation Type
Input File. Each item keeps its storage-location code. The program runs full validation,
creates the target batches, has a simulation mode (BAPI `TESTRUN`), restart by `RUN_ID`, and
logs every record in `ZLOT_MOV_EXEC`.

| File | Content |
|---|---|
| [`ZHBM_SPLIT_VAL_PH1.abap`](ZHBM_SPLIT_VAL_PH1.abap) | Executable report (SE38), with a numbered change log in its header |
| [`ZHBM_DDIC_TABLES.txt`](ZHBM_DDIC_TABLES.txt) | SE11 objects (`ZLOT_MOV_EXEC`, `ZLOT_BATCH_EXT`, data elements) and message class `ZHBM` |
| [`ZHBM_SPLIT_VAL_PH1_README.md`](ZHBM_SPLIT_VAL_PH1_README.md) | Technical documentation: processing logic, input file, modes, deployment, open points |

**Current version:** program v0.4, per `FSD_TSD_HBM_SplitValuation_Phase1_ZHBM_SPLIT_VAL_PH1_v0.4`
(the specifications are kept in the project document folder, not in this repository).

**Status:** not yet syntax-checked or run in an SAP system. See *To verify in the sandbox* in the
technical README before the first real run.
