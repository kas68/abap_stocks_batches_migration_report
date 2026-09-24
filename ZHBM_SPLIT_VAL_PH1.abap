*&---------------------------------------------------------------------*
*& Report  ZHBM_SPLIT_VAL_PH1
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Phase   : 1 - Clearing of batch stocks / Inter-plant transfer
*& Spec    : FSD_TSD_HBM_SplitValuation_Phase1_ZHBM_SPLIT_VAL_PH1 v0.3
*&           (supersedes Sfd_0001_0002_Out_In_V02)
*& Version : v0.3 (see change log)
*&
*& Purpose : Transfer unrestricted stock of batch-managed AND non-batch
*&           materials from source plant 8P01 to a newly created plant
*&           where Split Valuation is active, using movement type 301.
*&           Quantities and the material/batch/valuation-type mapping come
*&           from the HBM Valuation Type Input File.
*&
*& Processing (per FSD v0.3):
*&   3.1 Read SAP stock in 8P01 (unrestricted only), PER STORAGE LOCATION;
*&       flag batch mgmt.
*&   3.2 Presence in input file. Material/batch in SAP but NOT in file:
*&       if a valuation-type segment already exists in target plant ->
*&       inconsistency -> error logged, record not processed.
*&   3.3 Valuation-type (BWTAR) segment must exist in target plant,
*&       else error and record excluded.
*&   3.4 Batch creation in target plant (batch-managed only) via
*&       BAPI_BATCH_CREATE + BAPI_TRANSACTION_COMMIT, with the attributes
*&       of the source batch and the target valuation type. One valuation
*&       type per batch. Failure blocks 301.
*&   3.5 Quantity validation: file total per Material+Batch must equal
*&       available unrestricted SAP stock. Mismatch blocks. Zero-qty
*&       lines post no movement.
*&   3.6 Storage-location allocation, then post 301 with
*&       BAPI_GOODSMVT_CREATE (one document per input line, one ITEM per
*&       issuing storage location) + BAPI_TRANSACTION_COMMIT.
*&   4.  Historize every record in ZLOT_MOV_EXEC (one row per line and
*&       issuing storage location).
*&
*& Execution strategies (sec.5):
*&   - Full Validation Mode  : runs all checks 3.2 - 3.5 (default).
*&   - Direct Transfer Mode  : bypasses the validation logic; used for
*&                             materials without Split Valuation yet active
*&                             in the target plant.
*& Simulation (sec.7): P_TEST = 'X' (TESTRUN) - no movement, full logging.
*& RUN_ID / restart (sec.6): each run = RUN_ID + incremental sequence
*&   (001,002,...). A restart can target error-only lines.
*& Maintenance (sec.5): P_DEL deletes a RUN_ID from the Z tables only.
*&
*&---------------------------------------------------------------------*
*& Change log
*&---------------------------------------------------------------------*
*& v0.1  Initial version.
*& v0.2  Corrections raised by the FSD / source cross-check:
*&       [1] Storage location. Stock is now read per LGORT; an input line
*&           is allocated across the issuing storage locations that hold
*&           the stock (largest remaining first) and STGE_LOC /
*&           MOVE_STLOC are populated. Receiving location = P_LGDST.
*&           Without this the 301 posting could never succeed.
*&       [2] Selection-screen validations added (T001W, source <> target,
*&           T001L, separator, server file readable).
*&       [3] F_CHECK_SAP_NOT_IN_FILE is skipped when reprocessing error
*&           lines only; it previously re-logged every untouched stock
*&           record as I / X on each restart.
*&       [4] F_LOAD_PREV_ERRORS uses SELECT DISTINCT (duplicate keys
*&           dumped on the sorted unique table) and warns when the
*&           previous sequence holds status I records, which a
*&           reprocess-errors-only run cannot pick up.
*&       [5] Malformed, non-numeric and negative input lines are now
*&           rejected with status E and logged instead of being dropped
*&           silently.
*&       [6] Batch-extension failure message is memorised per
*&           material/batch, so every line of the same batch logs the
*&           BAPI message.
*&       [7] New check: input line with no unrestricted stock in the
*&           source plant reports ZHBM 006 instead of a misleading
*&           quantity-mismatch (ZHBM 004).
*&       [8] Posting date is a selection-screen parameter (P_BUDAT).
*&       [9] ALV now mirrors ZLOT_MOV_EXEC (run, plants, locations,
*&           message keys) as specified in FSD 4.4.2.
*&      [14] Default value 8Q01 for the target plant (P_WDST). It stays
*&           obligatory and is still checked against T001W and against
*&           the source plant, so the default is a convenience only.
*&      [13] Material type added to the selection screen (S_MTART).
*&           It restricts the stock selection and the input file to the
*&           material types chosen. MARC is still read without that
*&           restriction, so that a material left out by the type can
*&           be told apart from one not extended to the plant.
*&      [12] The NO_BATCH declaration is verified three ways, so that
*&           "not batch-managed" is established and not assumed:
*&           the plant indicator MARC-XCHPF of BOTH plants, the
*&           client-level indicator MARA-XCHPF, and the absence of
*&           unrestricted batch stock in MCHB for the source plant
*&           (ZHBM 015). The last one catches a material whose batch
*&           indicator was removed after batches had been created.
*&      [11] NO_BATCH is a declared value of the input file, not a
*&           placeholder: it states that the material is not
*&           batch-managed in the source plant nor in the target plant.
*&           The declaration is verified against MARC-XCHPF of BOTH
*&           plants (ZHBM 013) and against the extension of the material
*&           to the target plant (ZHBM 014); no batch is created and the
*&           301 carries the valuation type only. Such a line raises no
*&           ZHBM 012 warning, since it follows the convention.
*&      [10] Batch field normalisation. A placeholder value such as
*&           NO_BATCH in the batch column of the input file is reduced
*&           to blank, and any batch value is cleared for a material
*&           that is not batch-managed (MARC-XCHPF). Without this the
*&           file key never matches the stock key: the line was blocked
*&           with ZHBM 006 and the corresponding stock was reported as
*&           inconsistent (ZHBM 010), for every non-batch material.
*& v0.3  Corrections raised by the code review:
*&      [15] Receiving valuation type. The target valuation type is now
*&           passed in MOVE_VAL_TYPE (receiving side); VAL_TYPE (issuing
*&           side) stays blank, since the source plant is not
*&           split-valuated.
*&      [16] One valuation type per batch. With split valuation a batch
*&           carries a single valuation type (MCHA-BWTAR). A Material +
*&           Batch split over several valuation types in the input file
*&           is rejected (ZHBM 016); a batch that already exists in the
*&           target plant with another valuation type blocks the line
*&           (ZHBM 019).
*&      [17] Batch creation copies the attributes of the source batch
*&           (BAPI_BATCH_GET_DETAIL: expiry date, production date, vendor
*&           batch, ...) and sets the target valuation type. RETURN of
*&           BAPI_BATCH_CREATE is a TABLES parameter. An unreadable
*&           source batch blocks the line (ZHBM 020).
*&      [18] Direct Transfer Mode: the valuation type is posted only when
*&           the material is split-valuated in the target plant
*&           (MBEW-BWTTY); otherwise the 301 is posted without it and the
*&           record says so.
*&      [19] Unit of measure: the file unit is converted to the internal
*&           unit (CONVERSION_EXIT_CUNIT_INPUT, e.g. PC -> ST; ZHBM 017)
*&           and must equal the base unit of the material (ZHBM 018). A
*&           blank unit is read as the base unit.
*&      [20] Logs are persisted in the same LUW as each posting: pending
*&           rows are written before any BAPI call, and the rows of a
*&           posted document are committed with it. A failed update after
*&           the commit is written back to the log (ZHBM 022). The number
*&           of rows inserted is checked.
*&      [21] Simulation calls BAPI_GOODSMVT_CREATE with TESTRUN = 'X'
*&           followed by a rollback, so the posting itself is checked.
*&      [22] P_DEL: authorization check (S_TABU_NAM) and refusal when the
*&           RUN_ID holds posted material documents.
*&      [23] Selection-screen checks run on execution only (not on the
*&           radio-button switch). P_LGDST and P_BUDAT are checked there
*&           instead of OBLIGATORY, so the delete path needs neither.
*&      [24] CONVERSION_EXIT_MATN1_INPUT exceptions caught (ZHBM 009).
*&      [25] Performance: MBEW of the target plant buffered once; MCHB
*&           filtered on CLABS > 0 in the database; sorted look-up table
*&           for the NO_BATCH stock check.
*&---------------------------------------------------------------------*
REPORT zhbm_split_val_ph1 LINE-SIZE 200.

TYPE-POOLS: abap, slis.

*&---------------------------------------------------------------------*
*&  Constants
*&---------------------------------------------------------------------*
CONSTANTS:
  gc_mov_type   TYPE bwart      VALUE '301',
  gc_gm_code    TYPE bapi2017_gm_code-gm_code VALUE '04',   " MB1B transfer
  gc_xchpf      TYPE marc-xchpf VALUE 'X',
  gc_msgid      TYPE symsgid    VALUE 'ZHBM',
* run mode
  gc_mode_full  TYPE c VALUE 'F',
  gc_mode_dir   TYPE c VALUE 'D',
* status codes (domain ZLOT_STATUS)
  gc_st_ok      TYPE c VALUE 'S',   " success / posted
  gc_st_err     TYPE c VALUE 'E',   " error / blocked / excluded
  gc_st_warn    TYPE c VALUE 'W',
  gc_st_test    TYPE c VALUE 'T',   " simulation, not posted
  gc_st_zero    TYPE c VALUE 'Z',   " zero quantity - no movement
  gc_st_skip    TYPE c VALUE 'X',   " skipped (reconciliation)
  gc_st_incons  TYPE c VALUE 'I'.   " inconsistent (SAP not in file)

CONSTANTS:
* storage-location pool: consume / give back
  gc_take       TYPE i VALUE -1,
  gc_back       TYPE i VALUE 1.

* Placeholder values accepted in the batch column of the input file and
* reduced to blank. The specification asks for a blank batch on a
* non-batch-managed material; these tokens are tolerated because the
* extracts produced outside SAP commonly carry one of them. Extend the
* list here if HBM delivers another convention.
* Declared value of the batch column stating that the material is not
* batch-managed, neither in the source plant nor in the target plant.
* The program verifies the declaration against the material master and
* posts the 301 with the valuation type only, without any batch.
CONSTANTS:
  gc_no_batch    TYPE string VALUE 'NO_BATCH,NOBATCH,NO-BATCH,NO BATCH'.

* Other values tolerated in the batch column and reduced to blank. These
* are deviations from the convention, not declarations: they raise the
* ZHBM 012 warning.
CONSTANTS:
  gc_dummy_batch TYPE string VALUE 'N/A,NA,NONE,NULL,-,--,#,.'.

*&---------------------------------------------------------------------*
*&  Types
*&---------------------------------------------------------------------*
* input file raw record (one physical line)
TYPES: BEGIN OF ty_input_raw,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
         menge TYPE menge_d,
         meins TYPE meins,
         norm  TYPE abap_bool,   " batch value was normalised to blank
         nobat TYPE abap_bool,   " line declares NO_BATCH
         bad   TYPE abap_bool,   " declaration refused, line blocked
         badno TYPE symsgno,     " message number of the refusal
         badtx TYPE bapi_msg,    " message text of the refusal
       END OF ty_input_raw.
TYPES: tt_input_raw TYPE STANDARD TABLE OF ty_input_raw WITH DEFAULT KEY.

* input file aggregated per MATNR + CHARG (for quantity validation)
TYPES: BEGIN OF ty_input_sum,
         matnr TYPE matnr,
         charg TYPE charg_d,
         menge TYPE menge_d,
         meins TYPE meins,
       END OF ty_input_sum.
TYPES: tt_input_sum TYPE SORTED TABLE OF ty_input_sum
                    WITH UNIQUE KEY matnr charg.

* material master buffer: batch-management flag and base unit
TYPES: BEGIN OF ty_marc,
         matnr    TYPE matnr,
         werks    TYPE werks_d,
         mtart    TYPE mtart,      " MARA-MTART, material type
         xchpf    TYPE xchpf,      " MARC-XCHPF, plant level
         xchpf_cl TYPE xchpf,      " MARA-XCHPF, client level
         meins    TYPE meins,
         batchmgd TYPE abap_bool,  " derived: batch-managed in that plant
       END OF ty_marc.
TYPES: tt_marc TYPE SORTED TABLE OF ty_marc WITH UNIQUE KEY matnr werks.

* materials whose NO_BATCH declaration was refused: their stock must not
* be reported a second time by the reconciliation
TYPES: tt_matnr TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line.

* Material + Batch keys blocked by a line-level check (unit of measure,
* several valuation types for one batch): their stock must not be
* reported again by the reconciliation                         [v0.3-16]
TYPES: BEGIN OF ty_badkey,
         matnr TYPE matnr,
         charg TYPE charg_d,
       END OF ty_badkey.
TYPES: tt_badkey TYPE SORTED TABLE OF ty_badkey WITH UNIQUE KEY matnr charg.

* valuation segments of the target plant, buffered once       [v0.3-25]
TYPES: BEGIN OF ty_mbew,
         matnr TYPE matnr,
         bwtar TYPE bwtar_d,
         bwtty TYPE bwtty_d,      " valuation category (header row)
       END OF ty_mbew.
TYPES: tt_mbew TYPE SORTED TABLE OF ty_mbew WITH UNIQUE KEY matnr bwtar.

* SAP unrestricted stock per MATNR + CHARG (+ batch-mgmt flag), all LGORT
TYPES: BEGIN OF ty_stock,
         matnr TYPE matnr,
         charg TYPE charg_d,
         werks TYPE werks_d,
         xchpf TYPE xchpf,
         menge TYPE menge_d,
         meins TYPE meins,
       END OF ty_stock.
TYPES: tt_stock TYPE SORTED TABLE OF ty_stock
               WITH UNIQUE KEY matnr charg.

* SAP unrestricted stock per MATNR + CHARG + LGORT (issuing side)
TYPES: BEGIN OF ty_stock_loc,
         matnr TYPE matnr,
         charg TYPE charg_d,
         lgort TYPE lgort_d,
         menge TYPE menge_d,      " stock read
         remng TYPE menge_d,      " remaining, not yet allocated in this run
         meins TYPE meins,
       END OF ty_stock_loc.
TYPES: tt_stock_loc TYPE SORTED TABLE OF ty_stock_loc
                    WITH UNIQUE KEY matnr charg lgort.

* allocation of one input line over the issuing storage locations
TYPES: BEGIN OF ty_alloc,
         lgort TYPE lgort_d,
         menge TYPE menge_d,
       END OF ty_alloc.
TYPES: tt_alloc TYPE STANDARD TABLE OF ty_alloc WITH DEFAULT KEY.

* previous-run error keys (for restart of error lines)
TYPES: BEGIN OF ty_errkey,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
       END OF ty_errkey.
TYPES: tt_errkey TYPE SORTED TABLE OF ty_errkey
                WITH UNIQUE KEY matnr charg bwtar.

* memorised batch-extension result for the run
TYPES: BEGIN OF ty_done,
         matnr TYPE matnr,
         charg TYPE charg_d,
         ok    TYPE abap_bool,
         msg   TYPE bapi_msg,
         id    TYPE symsgid,
         no    TYPE symsgno,
         ty    TYPE symsgty,
       END OF ty_done.
TYPES: tt_done TYPE SORTED TABLE OF ty_done WITH UNIQUE KEY matnr charg.

* ALV / output row - mirrors ZLOT_MOV_EXEC (FSD 4.4.2)
TYPES: BEGIN OF ty_out,
         run_id     TYPE zlot_run_id,
         run_seq    TYPE numc3,
         run_mode   TYPE c,
         testrun    TYPE abap_bool,
         matnr      TYPE matnr,
         charg      TYPE charg_d,
         xchpf      TYPE xchpf,
         bwtar      TYPE bwtar_d,
         werks_src  TYPE werks_d,
         werks_dst  TYPE werks_d,
         lgort_src  TYPE lgort_d,
         lgort_dst  TYPE lgort_d,
         menge_post TYPE menge_d,     " quantity of this posting line
         qty_input  TYPE menge_d,     " quantity of the input file line
         qty_sap    TYPE menge_d,
         variance   TYPE menge_d,
         meins      TYPE meins,
         status     TYPE c,
         mblnr      TYPE mblnr,
         mjahr      TYPE mjahr,
         msgty      TYPE symsgty,
         msgid      TYPE symsgid,
         msgno      TYPE symsgno,
         message    TYPE bapi_msg,
         normbat    TYPE abap_bool,   " batch value normalised to blank
       END OF ty_out.
TYPES: tt_out TYPE STANDARD TABLE OF ty_out WITH DEFAULT KEY.

*&---------------------------------------------------------------------*
*&  Local helper class (valuation-segment existence check)
*&  Assumption: valuation level = plant, so BWKEY = target plant.
*&  Without BWTAR -> "any valuation-type segment exists for the material".
*&---------------------------------------------------------------------*
CLASS lcl_help DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS seg_exists
      IMPORTING iv_matnr TYPE matnr
                iv_bwkey TYPE bwkey
                iv_bwtar TYPE bwtar_d OPTIONAL
      RETURNING VALUE(rv_exists) TYPE abap_bool.
*   True when the batch column holds a placeholder (see GC_DUMMY_BATCH)
*   rather than a real batch number.
    CLASS-METHODS is_dummy_batch
      IMPORTING iv_charg TYPE charg_d
      RETURNING VALUE(rv_dummy) TYPE abap_bool.
*   True when the batch column carries the NO_BATCH declaration.
    CLASS-METHODS is_no_batch
      IMPORTING iv_charg TYPE charg_d
      RETURNING VALUE(rv_no) TYPE abap_bool.
*   Buffers the valuation segments of one valuation area   [v0.3-25]
    CLASS-METHODS load_mbew
      IMPORTING iv_bwkey TYPE bwkey
                it_matnr TYPE tt_matnr.
*   True when the material is split-valuated in the valuation area,
*   i.e. its MBEW header row carries a valuation category   [v0.3-18]
    CLASS-METHODS is_split_valuated
      IMPORTING iv_matnr TYPE matnr
                iv_bwkey TYPE bwkey
      RETURNING VALUE(rv_split) TYPE abap_bool.
  PRIVATE SECTION.
    CLASS-DATA: gt_mbew  TYPE tt_mbew,
                gv_bwkey TYPE bwkey.
    CLASS-METHODS in_list
      IMPORTING iv_val TYPE charg_d
                iv_list TYPE string
      RETURNING VALUE(rv_hit) TYPE abap_bool.
ENDCLASS.

CLASS lcl_help IMPLEMENTATION.
  METHOD seg_exists.
    DATA lv_x TYPE matnr.
*   buffered valuation area                                  [v0.3-25]
    IF gv_bwkey IS NOT INITIAL AND iv_bwkey = gv_bwkey.
      rv_exists = abap_false.
      IF iv_bwtar IS INITIAL.
        LOOP AT gt_mbew TRANSPORTING NO FIELDS
             WHERE matnr = iv_matnr AND bwtar <> space.
          rv_exists = abap_true.
          EXIT.
        ENDLOOP.
      ELSE.
        READ TABLE gt_mbew TRANSPORTING NO FIELDS
             WITH TABLE KEY matnr = iv_matnr bwtar = iv_bwtar.
        rv_exists = xsdbool( sy-subrc = 0 ).
      ENDIF.
      RETURN.
    ENDIF.
    IF iv_bwtar IS INITIAL.
      SELECT SINGLE matnr FROM mbew INTO lv_x
        WHERE matnr = iv_matnr
          AND bwkey = iv_bwkey
          AND bwtar <> space.
    ELSE.
      SELECT SINGLE matnr FROM mbew INTO lv_x
        WHERE matnr = iv_matnr
          AND bwkey = iv_bwkey
          AND bwtar = iv_bwtar.
    ENDIF.
    rv_exists = COND #( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).
  ENDMETHOD.

  METHOD load_mbew.
    CLEAR gt_mbew.
    gv_bwkey = iv_bwkey.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT matnr, bwtar, bwtty
      INTO CORRESPONDING FIELDS OF TABLE @gt_mbew
      FROM mbew
      FOR ALL ENTRIES IN @it_matnr
      WHERE matnr = @it_matnr-table_line
        AND bwkey = @iv_bwkey.
  ENDMETHOD.

  METHOD is_split_valuated.
    DATA ls_mbew TYPE ty_mbew.
    IF gv_bwkey IS NOT INITIAL AND iv_bwkey = gv_bwkey.
      READ TABLE gt_mbew INTO ls_mbew
           WITH TABLE KEY matnr = iv_matnr bwtar = space.
      rv_split = xsdbool( sy-subrc = 0 AND ls_mbew-bwtty IS NOT INITIAL ).
      RETURN.
    ENDIF.
    SELECT SINGLE bwtty FROM mbew INTO @DATA(lv_bwtty)
      WHERE matnr = @iv_matnr
        AND bwkey = @iv_bwkey
        AND bwtar = @space.
    rv_split = xsdbool( sy-subrc = 0 AND lv_bwtty IS NOT INITIAL ).
  ENDMETHOD.

  METHOD in_list.
    DATA: lt_tok TYPE STANDARD TABLE OF string,
          lv_tok TYPE string,
          lv_val TYPE string.
    rv_hit = abap_false.
    IF iv_val IS INITIAL.
      RETURN.
    ENDIF.
    lv_val = iv_val.
    CONDENSE lv_val.
    TRANSLATE lv_val TO UPPER CASE.
    SPLIT iv_list AT ',' INTO TABLE lt_tok.
    LOOP AT lt_tok INTO lv_tok.
      CONDENSE lv_tok.
      IF lv_tok IS NOT INITIAL AND lv_val = lv_tok.
        rv_hit = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_dummy_batch.
    rv_dummy = in_list( iv_val = iv_charg iv_list = gc_dummy_batch ).
  ENDMETHOD.

  METHOD is_no_batch.
    rv_no = in_list( iv_val = iv_charg iv_list = gc_no_batch ).
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*&  Global data
*&---------------------------------------------------------------------*
DATA: gt_input_raw TYPE tt_input_raw,
      gt_input_sum TYPE tt_input_sum,
      gt_marc      TYPE tt_marc,
      gt_badmat    TYPE tt_matnr,
      gt_badkey    TYPE tt_badkey,
      gt_stock     TYPE tt_stock,
      gt_stock_loc TYPE tt_stock_loc,
      gt_errkey    TYPE tt_errkey,
      gt_out       TYPE tt_out,
      gt_mov_log   TYPE STANDARD TABLE OF zlot_mov_exec,
      gt_ext_log   TYPE STANDARD TABLE OF zlot_batch_ext,
      gv_run_id    TYPE zlot_run_id,
      gv_run_seq   TYPE numc3,
      gv_run_mode  TYPE c,
      gv_posnr     TYPE numc6.

*&---------------------------------------------------------------------*
*&  Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  PARAMETERS: p_wsrc TYPE werks_d OBLIGATORY DEFAULT '8P01',   " source plant
              p_wdst TYPE werks_d OBLIGATORY DEFAULT '8Q01',    " target plant
              p_lgdst TYPE lgort_d.        " receiving stor.loc. (checked on execution) [v0.3-23]
  SELECT-OPTIONS: s_matnr FOR gt_stock-matnr,                   " optional filter
                  s_charg FOR gt_stock-charg,
                  s_mtart FOR gt_marc-mtart.                    " material type
  PARAMETERS: p_budat TYPE budat DEFAULT sy-datum.              " posting date (mandatory on execution)
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_srv RADIOBUTTON GROUP src DEFAULT 'X'            " app server
                    USER-COMMAND src,
              p_loc RADIOBUTTON GROUP src.                       " local (GUI upload)
  PARAMETERS: p_file TYPE string LOWER CASE,
              p_sep  TYPE c DEFAULT ';'.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: p_runid TYPE zlot_run_id,                          " blank = new RUN_ID
              p_reprc TYPE abap_bool AS CHECKBOX.                " reprocess error lines only
  PARAMETERS: p_full  RADIOBUTTON GROUP mod DEFAULT 'X',         " Full Validation Mode
              p_dir   RADIOBUTTON GROUP mod.                     " Direct Transfer Mode
  PARAMETERS: p_test  TYPE abap_bool DEFAULT 'X' AS CHECKBOX.    " TESTRUN (simulation)
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-b04.
  PARAMETERS: p_del TYPE abap_bool AS CHECKBOX.                  " delete RUN_ID (Z tables only)
SELECTION-SCREEN END OF BLOCK b4.

*&---------------------------------------------------------------------*
*&  F4 help for the input file path (local and application server)
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  IF p_loc = abap_true.
    DATA: lt_ftab TYPE filetable,
          lv_rc   TYPE i,
          lv_usr  TYPE abap_bool.
    CALL METHOD cl_gui_frontend_services=>file_open_dialog
      EXPORTING window_title = 'Select HBM Valuation Type Input File'
      CHANGING  file_table   = lt_ftab
                rc           = lv_rc
                user_action  = lv_usr.
    IF lv_usr = cl_gui_frontend_services=>action_ok.
      READ TABLE lt_ftab INDEX 1 INTO p_file.
    ENDIF.
  ELSE.
*   application server directory browser (FSD 4.2 / 5.1.4)
    DATA lv_srvfile TYPE dxfields-longpath.
    CALL FUNCTION 'F4_DXFILENAME_TOPRECURSION'
      EXPORTING
        i_location_flag = 'A'              " application server
        i_server        = ' '
        i_path          = p_file
        filemask        = '*.*'
        fileoperation   = 'R'
      IMPORTING
        o_path          = lv_srvfile
      EXCEPTIONS
        rfc_error             = 1
        error_with_gui        = 2
        OTHERS                = 3.
    IF sy-subrc = 0 AND lv_srvfile IS NOT INITIAL.
      p_file = lv_srvfile.
    ENDIF.
  ENDIF.

*&---------------------------------------------------------------------*
*&  Screen consistency                                        [v0.2 - 2]
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.

* Checks run only when the report is executed (F8, background job,
* print), not on every user command such as the switch between server
* and local file.                                            [v0.3-23]
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.

  IF p_del = abap_true.
*   maintenance path: only the RUN_ID is relevant
    IF p_runid IS INITIAL.
      MESSAGE 'RUN_ID is required for the delete/maintenance option' TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.

* --- plants -----------------------------------------------------------
  SELECT SINGLE werks FROM t001w INTO @DATA(lv_w)
    WHERE werks = @p_wsrc.
  IF sy-subrc <> 0.
    MESSAGE |Source plant { p_wsrc } does not exist (T001W)| TYPE 'E'.
  ENDIF.

  SELECT SINGLE werks FROM t001w INTO @lv_w
    WHERE werks = @p_wdst.
  IF sy-subrc <> 0.
    MESSAGE |Target plant { p_wdst } does not exist (T001W)| TYPE 'E'.
  ENDIF.

  IF p_wsrc = p_wdst.
    MESSAGE 'Source and target plant must be different' TYPE 'E'.
  ENDIF.

* --- mandatory on execution (not OBLIGATORY: the delete path needs
*     neither)                                                [v0.3-23]
  IF p_lgdst IS INITIAL.
    MESSAGE 'Receiving storage location is required' TYPE 'E'.
  ENDIF.
  IF p_budat IS INITIAL.
    MESSAGE 'Posting date is required' TYPE 'E'.
  ENDIF.

* --- receiving storage location ---------------------------------------
  SELECT SINGLE lgort FROM t001l INTO @DATA(lv_l)
    WHERE werks = @p_wdst AND lgort = @p_lgdst.
  IF sy-subrc <> 0.
    MESSAGE |Storage location { p_lgdst } does not exist in plant { p_wdst } (T001L)| TYPE 'E'.
  ENDIF.

* --- separator --------------------------------------------------------
  IF p_sep IS INITIAL.
    MESSAGE 'A field separator is required' TYPE 'E'.
  ENDIF.

* --- input file -------------------------------------------------------
  IF p_file IS INITIAL.
    MESSAGE 'Please specify the input file path' TYPE 'E'.
  ENDIF.

  IF p_srv = abap_true.
    OPEN DATASET p_file FOR INPUT IN TEXT MODE ENCODING DEFAULT.
    IF sy-subrc <> 0.
      MESSAGE |Input file not found or not readable on the application server: { p_file }| TYPE 'E'.
    ENDIF.
    CLOSE DATASET p_file.
  ELSE.
    DATA lv_exists TYPE abap_bool.
    CALL METHOD cl_gui_frontend_services=>file_exist
      EXPORTING  file   = p_file
      RECEIVING  result = lv_exists
      EXCEPTIONS OTHERS = 1.
    IF sy-subrc = 0 AND lv_exists = abap_false.
      MESSAGE |Local input file not found: { p_file }| TYPE 'E'.
    ENDIF.
  ENDIF.

* --- restart ----------------------------------------------------------
  IF p_reprc = abap_true.
    IF p_runid IS INITIAL.
      MESSAGE 'Reprocess-errors requires an existing RUN_ID' TYPE 'E'.
    ENDIF.
    SELECT SINGLE run_id FROM zlot_mov_exec INTO @DATA(lv_r)
      WHERE run_id = @p_runid.
    IF sy-subrc <> 0.
      MESSAGE |RUN_ID { p_runid } does not exist in ZLOT_MOV_EXEC| TYPE 'E'.
    ENDIF.
  ENDIF.

*&---------------------------------------------------------------------*
*&  Main
*&---------------------------------------------------------------------*
START-OF-SELECTION.

* Maintenance path: delete a RUN_ID from Z tables and stop.
  IF p_del = abap_true.
    PERFORM f_delete_run.
    RETURN.
  ENDIF.

* Also enforced here: a background job does not pass the screen
* checks of AT SELECTION-SCREEN.                             [v0.3-23]
  IF p_lgdst IS INITIAL OR p_budat IS INITIAL.
    MESSAGE 'Receiving storage location and posting date are required' TYPE 'E'.
  ENDIF.

  PERFORM f_init.

* 3.1 - read stock and input file
  PERFORM f_read_input CHANGING gt_input_raw.
  IF gt_input_raw IS INITIAL.
    PERFORM f_save_logs.                     " keep the rejected lines
    MESSAGE 'No usable line in the input file - see the log for rejected lines' TYPE 'E'.
  ENDIF.
* Batch column normalisation must happen before the aggregation, since
* it changes the Material + Batch key of the file.              [v0.2-10]
  PERFORM f_read_marc.
  PERFORM f_filter_mtart.
  PERFORM f_validate_no_batch.
  PERFORM f_normalise_batch.
* unit of measure and one valuation type per batch       [v0.3-16, 19]
  PERFORM f_validate_lines.

  PERFORM f_aggregate_input.
  PERFORM f_read_sap_stock.

* Restart of error lines only (sec.6)
  IF p_reprc = abap_true.
    PERFORM f_load_prev_errors.
  ENDIF.

* 3.2 - materials/batches in SAP but not in file (inconsistency check).
*       Skipped on a reprocess-errors-only run: the input set is then a
*       subset by construction and every untouched record would be
*       re-logged as I / X.                                   [v0.2 - 3]
  IF p_reprc = abap_false.
    PERFORM f_check_sap_not_in_file.
  ENDIF.

* 3.2 - 3.6 - process every input line
  PERFORM f_process_lines.

* 4. - persist
  PERFORM f_save_logs.

END-OF-SELECTION.
  PERFORM f_display_alv.

*&---------------------------------------------------------------------*
*&      Form  F_INIT   (resolve RUN_ID + sequence + mode)
*&---------------------------------------------------------------------*
FORM f_init.

  CLEAR: gt_out, gt_mov_log, gv_posnr.

  gv_run_mode = COND #( WHEN p_dir = abap_true THEN gc_mode_dir
                                               ELSE gc_mode_full ).

* RUN_ID: use given one or generate a new base id.
  IF p_runid IS INITIAL.
    gv_run_id = |HBM{ sy-datum }{ sy-uzeit }|.    " new base RUN_ID
  ELSE.
    gv_run_id = p_runid.
  ENDIF.

* Sequence: next incremental attempt for this RUN_ID.
  SELECT MAX( run_seq ) INTO @DATA(lv_maxseq)
    FROM zlot_mov_exec
    WHERE run_id = @gv_run_id.
  IF sy-subrc = 0 AND lv_maxseq IS NOT INITIAL.
    gv_run_seq = lv_maxseq + 1.
  ELSE.
    gv_run_seq = 1.
  ENDIF.

  WRITE: / 'HBM Split Valuation - Phase 1'.
  WRITE: / 'RUN_ID:', gv_run_id, 'Seq:', gv_run_seq,
           'Mode:', COND string( WHEN gv_run_mode = gc_mode_dir
                                 THEN 'DIRECT' ELSE 'FULL' ).
  WRITE: / 'Transfer:', p_wsrc, '->', p_wdst, '/', p_lgdst,
           'Posting date:', p_budat.
  IF p_test = abap_true.
    WRITE: / '*** SIMULATION (TESTRUN) - no posting ***' COLOR COL_TOTAL.
  ENDIF.
  SKIP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DELETE_RUN   (maintenance - Z tables only)
*&---------------------------------------------------------------------*
FORM f_delete_run.

  DATA lv_answer TYPE c.

* The log is the audit trail of the migration: deletion needs the table
* authorization, and a run that posted documents is kept.  [v0.3-22]
  AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
    ID 'ACTVT' FIELD '02'
    ID 'TABLE' FIELD 'ZLOT_MOV_EXEC'.
  IF sy-subrc <> 0.
    MESSAGE 'No authorization to delete the log (S_TABU_NAM, ZLOT_MOV_EXEC)'
            TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SELECT SINGLE posnr FROM zlot_mov_exec INTO @DATA(lv_posted)
    WHERE run_id  = @p_runid
      AND status  = @gc_st_ok
      AND testrun = @space.
  IF sy-subrc = 0.
    MESSAGE |RUN_ID { p_runid } holds posted material documents - its log cannot be deleted|
            TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar      = 'Delete RUN_ID from Z tables'
      text_question = |Delete all Z-table entries for RUN_ID { p_runid }? | &&
                      |No stock movement is performed.|
      text_button_1 = 'Delete'
      text_button_2 = 'Cancel'
    IMPORTING
      answer        = lv_answer.

  IF lv_answer <> '1'.
    MESSAGE 'Deletion cancelled' TYPE 'S'.
    RETURN.
  ENDIF.

  DELETE FROM zlot_mov_exec  WHERE run_id = p_runid.
  DATA(lv_mov) = sy-dbcnt.
  DELETE FROM zlot_batch_ext WHERE run_id = p_runid.
  DATA(lv_ext) = sy-dbcnt.
  COMMIT WORK.

  MESSAGE |RUN_ID { p_runid } deleted: { lv_mov } mov. rows, { lv_ext } batch rows|
          TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_INPUT   (dispatch server / local)
*&---------------------------------------------------------------------*
FORM f_read_input CHANGING ct_raw TYPE tt_input_raw.
  DATA lt_lines TYPE STANDARD TABLE OF string.
  IF p_loc = abap_true.
    PERFORM f_read_lines_local  CHANGING lt_lines.
  ELSE.
    PERFORM f_read_lines_server CHANGING lt_lines.
  ENDIF.
  PERFORM f_parse_lines USING lt_lines CHANGING ct_raw.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_LINES_SERVER
*&---------------------------------------------------------------------*
FORM f_read_lines_server CHANGING ct_lines TYPE stringtab.
  DATA lv_line TYPE string.
  OPEN DATASET p_file FOR INPUT IN TEXT MODE ENCODING DEFAULT.
  IF sy-subrc <> 0.
    MESSAGE |Cannot open input file on server: { p_file }| TYPE 'E'.
  ENDIF.
  DO.
    READ DATASET p_file INTO lv_line.
    IF sy-subrc <> 0. EXIT. ENDIF.
    APPEND lv_line TO ct_lines.
  ENDDO.
  CLOSE DATASET p_file.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_LINES_LOCAL   (GUI_UPLOAD)
*&---------------------------------------------------------------------*
FORM f_read_lines_local CHANGING ct_lines TYPE stringtab.
  DATA: lt_data TYPE STANDARD TABLE OF string,
        lv_fn   TYPE string.
  lv_fn = p_file.
  CALL METHOD cl_gui_frontend_services=>gui_upload
    EXPORTING  filename = lv_fn
               filetype = 'ASC'
    CHANGING   data_tab = lt_data
    EXCEPTIONS file_open_error = 1 file_read_error = 2 no_batch = 3
               gui_refuse_filetransfer = 4 invalid_type = 5 no_authority = 6
               unknown_error = 7 bad_data_format = 8 header_not_allowed = 9
               separator_not_allowed = 10 header_too_long = 11
               unknown_dp_error = 12 access_denied = 13 dp_out_of_memory = 14
               disk_full = 15 dp_timeout = 16 not_supported_by_gui = 17
               error_no_gui = 18 OTHERS = 19.
  IF sy-subrc <> 0.
    MESSAGE |Cannot read local input file { p_file } (rc={ sy-subrc })| TYPE 'E'.
  ENDIF.
  ct_lines = lt_data.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PARSE_LINES                                   [v0.2 - 5]
*&      Line 1 is treated as the header when its quantity field is not
*&      numeric. Every other unusable line is rejected with status E and
*&      logged, instead of being dropped silently.
*&---------------------------------------------------------------------*
FORM f_parse_lines USING it_lines TYPE stringtab
                   CHANGING ct_raw TYPE tt_input_raw.
  DATA: lv_line  TYPE string,
        lt_field TYPE STANDARD TABLE OF string,
        ls_raw   TYPE ty_input_raw,
        ls_out   TYPE ty_out,
        lv_qty_c TYPE string,
        lv_idx   TYPE i,
        lv_num   TYPE abap_bool,
        lv_uom_ext TYPE meins.

  LOOP AT it_lines INTO lv_line.

    lv_idx = sy-tabix.

*   blank line -> ignored, no log
    IF lv_line IS INITIAL OR lv_line CO ' '.
      CONTINUE.
    ENDIF.

    SPLIT lv_line AT p_sep INTO TABLE lt_field.

*   --- structural check: 5 columns expected ---------------------------
    IF lines( lt_field ) < 5.
      IF lv_idx = 1.
        CONTINUE.                      " header with a different layout
      ENDIF.
      CLEAR ls_out.
      ls_out-status  = gc_st_err.
      ls_out-message = |Line { lv_idx }: { lines( lt_field ) } field(s) found, 5 expected | &&
                       |- check the separator '{ p_sep }' and the column count|.
      PERFORM f_add_log USING gc_msgid '009' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

    CLEAR ls_raw.
    READ TABLE lt_field INDEX 1 INTO ls_raw-matnr.
    READ TABLE lt_field INDEX 2 INTO ls_raw-charg.
    READ TABLE lt_field INDEX 3 INTO ls_raw-bwtar.
    READ TABLE lt_field INDEX 4 INTO lv_qty_c.
    READ TABLE lt_field INDEX 5 INTO ls_raw-meins.
    CONDENSE: ls_raw-matnr, ls_raw-charg, ls_raw-bwtar, ls_raw-meins, lv_qty_c.

*   --- quantity format ------------------------------------------------
    lv_num = COND #( WHEN lv_qty_c CO ' 0123456789.,-' AND lv_qty_c CA '0123456789'
                     THEN abap_true ELSE abap_false ).

    IF lv_num = abap_false.
      IF lv_idx = 1.
        CONTINUE.                      " header line -> skipped silently
      ENDIF.
      CLEAR ls_out.
      ls_out-matnr   = ls_raw-matnr.
      ls_out-charg   = ls_raw-charg.
      ls_out-bwtar   = ls_raw-bwtar.
      ls_out-meins   = ls_raw-meins.
      ls_out-status  = gc_st_err.
      ls_out-message = |Line { lv_idx }: quantity '{ lv_qty_c }' is not numeric - line rejected|.
      PERFORM f_add_log USING gc_msgid '007' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

    REPLACE ALL OCCURRENCES OF ',' IN lv_qty_c WITH '.'.
*   the character check above accepts patterns such as '1-2' or '1.2.3',
*   which still raise a conversion exception: catch it rather than dump
    TRY.
        ls_raw-menge = lv_qty_c.
      CATCH cx_sy_conversion_no_number.
        CLEAR ls_out.
        ls_out-matnr   = ls_raw-matnr.
        ls_out-charg   = ls_raw-charg.
        ls_out-bwtar   = ls_raw-bwtar.
        ls_out-meins   = ls_raw-meins.
        ls_out-status  = gc_st_err.
        ls_out-message = |Line { lv_idx }: quantity '{ lv_qty_c }' cannot be converted - line rejected|.
        PERFORM f_add_log USING gc_msgid '007' 'E' CHANGING ls_out.
        CONTINUE.
    ENDTRY.

    CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
      EXPORTING  input        = ls_raw-matnr
      IMPORTING  output       = ls_raw-matnr
      EXCEPTIONS length_error = 1
                 OTHERS       = 2.
    IF sy-subrc <> 0.                                       " [v0.3-24]
      CLEAR ls_out.
      ls_out-status  = gc_st_err.
      ls_out-message = |Line { lv_idx }: material number cannot be converted - line rejected|.
      PERFORM f_add_log USING gc_msgid '009' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.
    TRANSLATE: ls_raw-charg TO UPPER CASE,
               ls_raw-bwtar TO UPPER CASE,
               ls_raw-meins TO UPPER CASE.

*   --- unit of measure: file (external) -> internal, e.g. PC -> ST ---
*   A blank unit is read later as the base unit.             [v0.3-19]
    IF ls_raw-meins IS NOT INITIAL.
      lv_uom_ext = ls_raw-meins.
      CALL FUNCTION 'CONVERSION_EXIT_CUNIT_INPUT'
        EXPORTING  input          = lv_uom_ext
                   language       = sy-langu
        IMPORTING  output         = ls_raw-meins
        EXCEPTIONS unit_not_found = 1
                   OTHERS         = 2.
      IF sy-subrc <> 0.
        CLEAR ls_out.
        ls_out-matnr     = ls_raw-matnr.
        ls_out-charg     = ls_raw-charg.
        ls_out-bwtar     = ls_raw-bwtar.
        ls_out-qty_input = ls_raw-menge.
        ls_out-status    = gc_st_err.
        ls_out-message   = |Line { lv_idx }: unit of measure '{ lv_uom_ext }' unknown - line rejected|.
        PERFORM f_add_log USING gc_msgid '017' 'E' CHANGING ls_out.
        CONTINUE.
      ENDIF.
    ENDIF.

*   --- NO_BATCH declaration, or a tolerated placeholder -------------
    IF lcl_help=>is_no_batch( ls_raw-charg ) = abap_true.
*     declared convention: the material is not batch-managed in either
*     plant. Verified later against the material master.
      CLEAR ls_raw-charg.
      ls_raw-nobat = abap_true.
    ELSEIF lcl_help=>is_dummy_batch( ls_raw-charg ) = abap_true.
*     deviation from the convention, tolerated and reported
      CLEAR ls_raw-charg.
      ls_raw-norm = abap_true.
    ENDIF.

*   --- negative quantity ----------------------------------------------
    IF ls_raw-menge < 0.
      CLEAR ls_out.
      ls_out-matnr     = ls_raw-matnr.
      ls_out-charg     = ls_raw-charg.
      ls_out-bwtar     = ls_raw-bwtar.
      ls_out-qty_input = ls_raw-menge.
      ls_out-meins     = ls_raw-meins.
      ls_out-status    = gc_st_err.
      ls_out-message   = |Line { lv_idx }: negative quantity { ls_raw-menge } - line rejected|.
      PERFORM f_add_log USING gc_msgid '008' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

*   --- mandatory key fields -------------------------------------------
    IF ls_raw-matnr IS INITIAL OR ls_raw-bwtar IS INITIAL.
      CLEAR ls_out.
      ls_out-matnr     = ls_raw-matnr.
      ls_out-charg     = ls_raw-charg.
      ls_out-bwtar     = ls_raw-bwtar.
      ls_out-qty_input = ls_raw-menge.
      ls_out-meins     = ls_raw-meins.
      ls_out-status    = gc_st_err.
      ls_out-message   = |Line { lv_idx }: material and valuation type are mandatory - line rejected|.
      PERFORM f_add_log USING gc_msgid '009' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

*   selection-screen restriction (documented in FSD 4.2)
    CHECK ls_raw-matnr IN s_matnr AND ls_raw-charg IN s_charg.
    APPEND ls_raw TO ct_raw.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_MARC                                    [v0.2 - 10]
*&      Batch-management flag and base unit of measure of the materials
*&      of the source plant. Read once, used by the batch normalisation
*&      and by the stock selection.
*&---------------------------------------------------------------------*
FORM f_read_marc.
* both plants: the source plant drives the stock selection, the target
* plant is needed to verify a NO_BATCH declaration        [v0.2 - 11]
* S_MTART is deliberately NOT applied here. Knowing the type of every
* material of the plant lets the program tell a material excluded by
* the selected types from one that is not extended to the plant, which
* two different messages depend on.                        [v0.2 - 13]
  SELECT c~matnr, c~werks, a~mtart, c~xchpf, a~xchpf AS xchpf_cl, a~meins
    INTO CORRESPONDING FIELDS OF TABLE @gt_marc
    FROM marc AS c
    INNER JOIN mara AS a ON a~matnr = c~matnr
    WHERE ( c~werks = @p_wsrc OR c~werks = @p_wdst )
      AND c~matnr IN @s_matnr.

* A material is batch-managed in a plant when the plant indicator is
* set, or when the client-level indicator makes it mandatory
* everywhere. Testing MARC-XCHPF alone would classify a material that
* is managed only at client level as non-batch.            [v0.2 - 12]
  LOOP AT gt_marc ASSIGNING FIELD-SYMBOL(<ls_mrc>).
    IF <ls_mrc>-xchpf = gc_xchpf OR <ls_mrc>-xchpf_cl = gc_xchpf.
      <ls_mrc>-batchmgd = abap_true.
    ENDIF.
  ENDLOOP.

* Valuation segments of the target plant, read once instead of one
* SELECT per line and per stock record                     [v0.3-25]
  DATA lt_mat_dst TYPE tt_matnr.
  LOOP AT gt_marc INTO DATA(ls_mdst) WHERE werks = p_wdst.
    INSERT ls_mdst-matnr INTO TABLE lt_mat_dst.
  ENDLOOP.
  lcl_help=>load_mbew( iv_bwkey = p_wdst it_matnr = lt_mat_dst ).
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_FILTER_MTART                                 [v0.2 - 13]
*&      Restricts the input file to the material types selected. Lines
*&      whose material is unknown in the source plant are kept, so that
*&      they are still reported by ZHBM 006 or ZHBM 014 instead of
*&      disappearing silently.
*&---------------------------------------------------------------------*
FORM f_filter_mtart.

  DATA: ls_raw  TYPE ty_input_raw,
        ls_mrc  TYPE ty_marc,
        lt_keep TYPE tt_input_raw.

  IF s_mtart[] IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_input_raw INTO ls_raw.
    READ TABLE gt_marc INTO ls_mrc
         WITH KEY matnr = ls_raw-matnr werks = p_wsrc.
    IF sy-subrc = 0 AND ls_mrc-mtart NOT IN s_mtart.
      CONTINUE.                      " outside the selected material types
    ENDIF.
    APPEND ls_raw TO lt_keep.
  ENDLOOP.
  gt_input_raw = lt_keep.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_VALIDATE_NO_BATCH                            [v0.2 - 11]
*&      NO_BATCH in the batch column declares that the material is not
*&      batch-managed, neither in the source plant nor in the target
*&      plant. The declaration is verified against MARC-XCHPF of both
*&      plants before anything is posted, because it decides that no
*&      batch is created and that the 301 carries the valuation type
*&      alone. A declaration contradicted by the material master is a
*&      data problem and blocks the line with an explicit message,
*&      rather than surfacing later as a missing stock record.
*&---------------------------------------------------------------------*
FORM f_validate_no_batch.

  DATA: ls_raw TYPE ty_input_raw,
        ls_mrc TYPE ty_marc,
        lv_mat TYPE matnr.

* Nothing declared: no need to read the batch stock.
  READ TABLE gt_input_raw TRANSPORTING NO FIELDS WITH KEY nobat = abap_true.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

* Materials that actually carry unrestricted batch stock in the source
* plant. A material master can state that a material is not
* batch-managed while batches created earlier still hold stock; such a
* material cannot be transferred as a non-batch record, because the
* movement would have to address those batches.            [v0.2 - 12]
  DATA lt_with_batch TYPE tt_matnr.                          " [v0.3-25]
  SELECT DISTINCT matnr INTO TABLE @lt_with_batch
    FROM mchb
    WHERE werks =  @p_wsrc
      AND matnr IN @s_matnr
      AND clabs >  0.

  LOOP AT gt_input_raw INTO ls_raw WHERE nobat = abap_true.

    CLEAR: ls_raw-bad, ls_raw-badno, ls_raw-badtx.

*   --- source plant ------------------------------------------------
    READ TABLE gt_marc INTO ls_mrc
         WITH KEY matnr = ls_raw-matnr werks = p_wsrc.
    IF sy-subrc <> 0.
      ls_raw-bad   = abap_true.
      ls_raw-badno = '014'.
      ls_raw-badtx = |Material { ls_raw-matnr } is not extended to plant { p_wsrc }|.
    ELSEIF ls_mrc-batchmgd = abap_true.
      ls_raw-bad   = abap_true.
      ls_raw-badno = '013'.
      ls_raw-badtx = |Material { ls_raw-matnr } is batch-managed in plant { p_wsrc } | &&
                     |(MARC-XCHPF { ls_mrc-xchpf }, MARA-XCHPF { ls_mrc-xchpf_cl }) | &&
                     |but the input line declares NO_BATCH|.
    ELSE.
*     --- target plant ----------------------------------------------
      READ TABLE gt_marc INTO ls_mrc
           WITH KEY matnr = ls_raw-matnr werks = p_wdst.
      IF sy-subrc <> 0.
        ls_raw-bad   = abap_true.
        ls_raw-badno = '014'.
        ls_raw-badtx = |Material { ls_raw-matnr } is not extended to plant { p_wdst }|.
      ELSEIF ls_mrc-batchmgd = abap_true.
        ls_raw-bad   = abap_true.
        ls_raw-badno = '013'.
        ls_raw-badtx = |Material { ls_raw-matnr } is batch-managed in plant { p_wdst } | &&
                       |(MARC-XCHPF { ls_mrc-xchpf }, MARA-XCHPF { ls_mrc-xchpf_cl }) | &&
                       |but the input line declares NO_BATCH|.
      ELSE.
*       the master data agrees; confirm it against the stock itself
        READ TABLE lt_with_batch TRANSPORTING NO FIELDS
             WITH TABLE KEY table_line = ls_raw-matnr.
        IF sy-subrc = 0.
          ls_raw-bad   = abap_true.
          ls_raw-badno = '015'.
          ls_raw-badtx = |Material { ls_raw-matnr } declares NO_BATCH but holds | &&
                         |unrestricted batch stock in plant { p_wsrc } (MCHB)|.
        ENDIF.
      ENDIF.
    ENDIF.

    IF ls_raw-bad = abap_true.
      MODIFY gt_input_raw FROM ls_raw.
*     remember the material, so that its stock is not reported a second
*     time by the reconciliation of step 5
      lv_mat = ls_raw-matnr.
      READ TABLE gt_badmat TRANSPORTING NO FIELDS WITH KEY table_line = lv_mat.
      IF sy-subrc <> 0.
        INSERT lv_mat INTO TABLE gt_badmat.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_NORMALISE_BATCH                              [v0.2 - 10]
*&      The specification requires a blank batch for a non-batch-managed
*&      material. Files produced outside SAP often carry a placeholder
*&      instead (NO_BATCH and the like), and such a value would make the
*&      file key differ from the stock key: the line would be blocked
*&      with ZHBM 006 and the stock reported as inconsistent with
*&      ZHBM 010, for every non-batch-managed material.
*&      Two safeguards: the placeholder list handled in F_PARSE_LINES,
*&      and here any batch value carried by a material that is not
*&      batch-managed according to MARC-XCHPF. One warning row per run
*&      records how many lines were normalised, and each affected record
*&      carries the information in its message.
*&---------------------------------------------------------------------*
FORM f_normalise_batch.

  DATA: ls_raw TYPE ty_input_raw,
        ls_mrc TYPE ty_marc,
        ls_out TYPE ty_out,
        lv_cnt TYPE i.

  LOOP AT gt_input_raw INTO ls_raw.

*   already reduced to blank by the placeholder list
    IF ls_raw-charg IS INITIAL.
      IF ls_raw-norm = abap_true.
        lv_cnt = lv_cnt + 1.
      ENDIF.
      CONTINUE.
    ENDIF.

    READ TABLE gt_marc INTO ls_mrc
         WITH KEY matnr = ls_raw-matnr werks = p_wsrc.
    IF sy-subrc = 0 AND ls_mrc-batchmgd = abap_false.
*     the material is not batch-managed: whatever the file carries in
*     the batch column is not a batch
      CLEAR ls_raw-charg.
      ls_raw-norm = abap_true.
      MODIFY gt_input_raw FROM ls_raw.
      lv_cnt = lv_cnt + 1.
    ENDIF.
  ENDLOOP.

  IF lv_cnt > 0.
    CLEAR ls_out.
    ls_out-status  = gc_st_warn.
    ls_out-message = |{ lv_cnt } input line(s): batch column normalised to blank | &&
                     |(placeholder value, or material not batch-managed)|.
    PERFORM f_add_log USING gc_msgid '012' 'W' CHANGING ls_out.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_VALIDATE_LINES                             [v0.3-16, 19]
*&      Line-level checks that must run before the aggregation, since a
*&      blocked line is left out of the quantity reconciliation:
*&      - the unit of the file must be the base unit of the material
*&        (a blank unit is read as the base unit);
*&      - with split valuation a batch carries ONE valuation type
*&        (MCHA-BWTAR). A Material + Batch split over several valuation
*&        types in the file cannot be posted: every line of that batch
*&        is rejected, and HBM corrects the file (one valuation type per
*&        batch, or new batch numbers).
*&---------------------------------------------------------------------*
FORM f_validate_lines.

  DATA: ls_raw   TYPE ty_input_raw,
        ls_mrc   TYPE ty_marc,
        lt_vt    TYPE tt_errkey,          " MATNR + CHARG + BWTAR, unique
        ls_vt    TYPE ty_errkey,
        lt_multi TYPE tt_badkey,
        ls_key   TYPE ty_badkey.

* --- unit of measure = base unit -----------------------------------
  LOOP AT gt_input_raw INTO ls_raw WHERE bad = abap_false.
    READ TABLE gt_marc INTO ls_mrc
         WITH TABLE KEY matnr = ls_raw-matnr werks = p_wsrc.
    CHECK sy-subrc = 0.               " not extended: reported later
    IF ls_raw-meins IS INITIAL.
      ls_raw-meins = ls_mrc-meins.
      MODIFY gt_input_raw FROM ls_raw.
    ELSEIF ls_raw-meins <> ls_mrc-meins.
      ls_raw-bad   = abap_true.
      ls_raw-badno = '018'.
      ls_raw-badtx = |Unit { ls_raw-meins } differs from base unit { ls_mrc-meins } | &&
                     |of material { ls_raw-matnr } - give the quantity in the base unit|.
      MODIFY gt_input_raw FROM ls_raw.
      INSERT VALUE ty_badkey( matnr = ls_raw-matnr charg = ls_raw-charg )
             INTO TABLE gt_badkey.
    ENDIF.
  ENDLOOP.

* --- one valuation type per batch ------------------------------------
* Zero-quantity lines move nothing and do not count as a valuation type.
  LOOP AT gt_input_raw INTO ls_raw WHERE bad = abap_false AND charg IS NOT INITIAL
                                     AND menge <> 0.
    INSERT VALUE ty_errkey( matnr = ls_raw-matnr
                            charg = ls_raw-charg
                            bwtar = ls_raw-bwtar ) INTO TABLE lt_vt.
  ENDLOOP.

* lt_vt is sorted by MATNR, CHARG, BWTAR: a second row for the same
* MATNR + CHARG means a second valuation type
  CLEAR ls_key.
  LOOP AT lt_vt INTO ls_vt.
    IF ls_vt-matnr = ls_key-matnr AND ls_vt-charg = ls_key-charg.
      INSERT ls_key INTO TABLE lt_multi.
    ELSE.
      ls_key-matnr = ls_vt-matnr.
      ls_key-charg = ls_vt-charg.
    ENDIF.
  ENDLOOP.

  IF lt_multi IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT gt_input_raw INTO ls_raw WHERE bad = abap_false AND charg IS NOT INITIAL.
    READ TABLE lt_multi TRANSPORTING NO FIELDS
         WITH TABLE KEY matnr = ls_raw-matnr charg = ls_raw-charg.
    CHECK sy-subrc = 0.
    ls_raw-bad   = abap_true.
    ls_raw-badno = '016'.
    ls_raw-badtx = |Batch { ls_raw-charg } of material { ls_raw-matnr } is split over | &&
                   |several valuation types in the input file; a batch carries one | &&
                   |valuation type - batch rejected|.
    MODIFY gt_input_raw FROM ls_raw.
    INSERT VALUE ty_badkey( matnr = ls_raw-matnr charg = ls_raw-charg )
           INTO TABLE gt_badkey.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_AGGREGATE_INPUT   (sum per MATNR + CHARG)
*&---------------------------------------------------------------------*
FORM f_aggregate_input.
  DATA: ls_raw TYPE ty_input_raw,
        ls_sum TYPE ty_input_sum.
  LOOP AT gt_input_raw INTO ls_raw.
    CHECK ls_raw-bad = abap_false.        " blocked line, not reconciled
    READ TABLE gt_input_sum INTO ls_sum
         WITH KEY matnr = ls_raw-matnr charg = ls_raw-charg.
    IF sy-subrc = 0.
      ls_sum-menge = ls_sum-menge + ls_raw-menge.
      MODIFY TABLE gt_input_sum FROM ls_sum.
    ELSE.
      CLEAR ls_sum.
      ls_sum-matnr = ls_raw-matnr.
      ls_sum-charg = ls_raw-charg.
      ls_sum-menge = ls_raw-menge.
      ls_sum-meins = ls_raw-meins.
      INSERT ls_sum INTO TABLE gt_input_sum.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_SAP_STOCK                                [v0.2 - 1]
*&      Unrestricted stock only. Batch-managed -> MCHB-CLABS,
*&      non-batch -> MARD-LABST. Batch flag from MARC-XCHPF.
*&      Stock is kept twice: aggregated per MATNR+CHARG for the
*&      reconciliation, and per MATNR+CHARG+LGORT for the allocation of
*&      the issuing storage locations.
*&---------------------------------------------------------------------*
FORM f_read_sap_stock.

  DATA: ls_stk TYPE ty_stock,
        ls_loc TYPE ty_stock_loc.

* --- batch-managed materials: MCHB unrestricted (CLABS) per LGORT ---
  SELECT matnr, werks, lgort, charg, clabs
    INTO TABLE @DATA(lt_mchb)
    FROM mchb
    WHERE werks =  @p_wsrc
      AND matnr IN @s_matnr
      AND charg IN @s_charg
      AND clabs >  0.                                        " [v0.3-25]

  LOOP AT lt_mchb INTO DATA(ls_mchb).
    READ TABLE gt_marc INTO DATA(ls_marc)
         WITH KEY matnr = ls_mchb-matnr werks = p_wsrc.
    CHECK sy-subrc = 0 AND ls_marc-batchmgd = abap_true   " batch mats only
                      AND ls_marc-mtart IN s_mtart.
    CHECK ls_mchb-clabs > 0.

*   per storage location
    CLEAR ls_loc.
    ls_loc-matnr = ls_mchb-matnr.
    ls_loc-charg = ls_mchb-charg.
    ls_loc-lgort = ls_mchb-lgort.
    ls_loc-menge = ls_mchb-clabs.
    ls_loc-remng = ls_mchb-clabs.
    ls_loc-meins = ls_marc-meins.
    INSERT ls_loc INTO TABLE gt_stock_loc.

*   aggregated
    READ TABLE gt_stock INTO ls_stk
         WITH KEY matnr = ls_mchb-matnr charg = ls_mchb-charg.
    IF sy-subrc = 0.
      ls_stk-menge = ls_stk-menge + ls_mchb-clabs.
      MODIFY TABLE gt_stock FROM ls_stk.
    ELSE.
      CLEAR ls_stk.
      ls_stk-matnr = ls_mchb-matnr.
      ls_stk-charg = ls_mchb-charg.
      ls_stk-werks = ls_mchb-werks.
      ls_stk-xchpf = gc_xchpf.
      ls_stk-menge = ls_mchb-clabs.
      ls_stk-meins = ls_marc-meins.
      INSERT ls_stk INTO TABLE gt_stock.
    ENDIF.
  ENDLOOP.

* --- non-batch materials: MARD unrestricted (LABST) per LGORT -------
  SELECT matnr, werks, lgort, labst
    INTO TABLE @DATA(lt_mard)
    FROM mard
    WHERE werks =  @p_wsrc
      AND matnr IN @s_matnr.

  LOOP AT lt_mard INTO DATA(ls_mard).
    READ TABLE gt_marc INTO ls_marc
         WITH KEY matnr = ls_mard-matnr werks = p_wsrc.
    CHECK sy-subrc = 0 AND ls_marc-batchmgd = abap_false  " non-batch only
                      AND ls_marc-mtart IN s_mtart.
    CHECK ls_mard-labst > 0.

    CLEAR ls_loc.
    ls_loc-matnr = ls_mard-matnr.
    ls_loc-charg = space.
    ls_loc-lgort = ls_mard-lgort.
    ls_loc-menge = ls_mard-labst.
    ls_loc-remng = ls_mard-labst.
    ls_loc-meins = ls_marc-meins.
    INSERT ls_loc INTO TABLE gt_stock_loc.

    READ TABLE gt_stock INTO ls_stk
         WITH KEY matnr = ls_mard-matnr charg = space.
    IF sy-subrc = 0.
      ls_stk-menge = ls_stk-menge + ls_mard-labst.
      MODIFY TABLE gt_stock FROM ls_stk.
    ELSE.
      CLEAR ls_stk.
      ls_stk-matnr = ls_mard-matnr.
      ls_stk-charg = space.
      ls_stk-werks = ls_mard-werks.
      ls_stk-xchpf = space.
      ls_stk-menge = ls_mard-labst.
      ls_stk-meins = ls_marc-meins.
      INSERT ls_stk INTO TABLE gt_stock.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_ALLOCATE_LGORT                                [v0.2 - 1]
*&      Distributes the quantity of one input line over the issuing
*&      storage locations that still hold unallocated unrestricted
*&      stock, largest remaining first. The remaining pool is shared by
*&      all the valuation-type lines of the same material / batch, so
*&      the same quantity is never issued twice.
*&      Allocation rule to be confirmed by the business: largest-first
*&      (current) or pro rata.
*&---------------------------------------------------------------------*
FORM f_allocate_lgort USING iv_matnr TYPE matnr
                            iv_charg TYPE charg_d
                            iv_menge TYPE menge_d
                      CHANGING ct_alloc TYPE tt_alloc
                               cv_ok    TYPE abap_bool
                               cv_avail TYPE menge_d.

  DATA: lt_cand TYPE STANDARD TABLE OF ty_stock_loc,
        ls_loc  TYPE ty_stock_loc,
        ls_all  TYPE ty_alloc,
        lv_rest TYPE menge_d,
        lv_take TYPE menge_d.

  CLEAR: ct_alloc, cv_ok, cv_avail.
  lv_rest = iv_menge.

  LOOP AT gt_stock_loc INTO ls_loc
       WHERE matnr = iv_matnr AND charg = iv_charg.
    cv_avail = cv_avail + ls_loc-remng.
    IF ls_loc-remng > 0.
      APPEND ls_loc TO lt_cand.
    ENDIF.
  ENDLOOP.

  IF lt_cand IS INITIAL.
    cv_ok = abap_false.
    RETURN.
  ENDIF.

  SORT lt_cand BY remng DESCENDING lgort ASCENDING.

  LOOP AT lt_cand INTO ls_loc.
    IF lv_rest <= 0. EXIT. ENDIF.
    lv_take = COND menge_d( WHEN ls_loc-remng >= lv_rest THEN lv_rest
                                                         ELSE ls_loc-remng ).
    CLEAR ls_all.
    ls_all-lgort = ls_loc-lgort.
    ls_all-menge = lv_take.
    APPEND ls_all TO ct_alloc.
    lv_rest = lv_rest - lv_take.
  ENDLOOP.

  IF lv_rest > 0.
    CLEAR ct_alloc.                    " partial issue is not acceptable
    cv_ok = abap_false.
  ELSE.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_CONSUME_ALLOC
*&      iv_sign = -1 consume the allocated quantities, +1 give them back
*&      (posting failed, the stock is still available for another line).
*&---------------------------------------------------------------------*
FORM f_consume_alloc USING it_alloc TYPE tt_alloc
                           iv_matnr TYPE matnr
                           iv_charg TYPE charg_d
                           iv_sign  TYPE i.
  DATA: ls_all TYPE ty_alloc,
        ls_loc TYPE ty_stock_loc.
  LOOP AT it_alloc INTO ls_all.
    READ TABLE gt_stock_loc INTO ls_loc
         WITH KEY matnr = iv_matnr charg = iv_charg lgort = ls_all-lgort.
    CHECK sy-subrc = 0.
    ls_loc-remng = ls_loc-remng + ( iv_sign * ls_all-menge ).
    MODIFY TABLE gt_stock_loc FROM ls_loc.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_LOAD_PREV_ERRORS   (restart error-only lines, sec.6)
*&      Keep only input lines that errored in the latest prior attempt.
*&---------------------------------------------------------------------*
FORM f_load_prev_errors.

  DATA: lv_prevseq TYPE numc3.

  lv_prevseq = gv_run_seq - 1.
  IF lv_prevseq < 1.
    RETURN.                          " no prior attempt
  ENDIF.

* SELECT DISTINCT: the same MATNR/CHARG/BWTAR may appear on several rows
* of the previous sequence (one per issuing storage location), and
* GT_ERRKEY has a unique key.                                 [v0.2 - 4]
  SELECT DISTINCT matnr, charg, bwtar INTO TABLE @gt_errkey
    FROM zlot_mov_exec
    WHERE run_id  = @gv_run_id
      AND run_seq = @lv_prevseq
      AND status  = @gc_st_err.

* Status I records cannot be reprocessed this way: they are by
* definition absent from the input file and carry no valuation type.
* Warn the user, who must complete the file and start a full run.
  SELECT COUNT( * ) INTO @DATA(lv_inc)
    FROM zlot_mov_exec
    WHERE run_id  = @gv_run_id
      AND run_seq = @lv_prevseq
      AND status  = @gc_st_incons.
  IF lv_inc > 0.
    MESSAGE |{ lv_inc } inconsistent record(s) (status I) in sequence { lv_prevseq } | &&
            |are not reprocessed: complete the input file and run without | &&
            |'Reprocess error lines only'| TYPE 'I'.
  ENDIF.

  IF gt_errkey IS INITIAL.
    MESSAGE 'No error lines to reprocess for this RUN_ID' TYPE 'I'.
    CLEAR gt_input_raw.              " nothing to do
    RETURN.
  ENDIF.

* keep only raw lines that match a previous error key
  DATA lt_keep TYPE tt_input_raw.
  LOOP AT gt_input_raw INTO DATA(ls_raw).
    READ TABLE gt_errkey TRANSPORTING NO FIELDS
         WITH KEY matnr = ls_raw-matnr
                  charg = ls_raw-charg
                  bwtar = ls_raw-bwtar.
    IF sy-subrc = 0.
      APPEND ls_raw TO lt_keep.
    ENDIF.
  ENDLOOP.
  gt_input_raw = lt_keep.
* rebuild aggregation on the reduced set
  CLEAR gt_input_sum.
  PERFORM f_aggregate_input.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_CHECK_SAP_NOT_IN_FILE   (3.2 case 2)
*&      SAP stock not present in file: if a valuation-type segment
*&      already exists in target plant -> inconsistency -> error logged.
*&---------------------------------------------------------------------*
FORM f_check_sap_not_in_file.

  DATA: ls_stk TYPE ty_stock,
        ls_out TYPE ty_out.

  IF gv_run_mode = gc_mode_dir.
    RETURN.                          " Direct mode bypasses validations
  ENDIF.

  LOOP AT gt_stock INTO ls_stk.
    READ TABLE gt_input_sum TRANSPORTING NO FIELDS
         WITH KEY matnr = ls_stk-matnr charg = ls_stk-charg.
    IF sy-subrc = 0.
      CONTINUE.                      " present in file -> handled elsewhere
    ENDIF.

*   the material is already reported through its refused NO_BATCH
*   declaration; do not raise a second, confusing message [v0.2 - 11]
    READ TABLE gt_badmat TRANSPORTING NO FIELDS
         WITH KEY table_line = ls_stk-matnr.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

*   same for a Material + Batch blocked by a line-level check [v0.3-16]
    READ TABLE gt_badkey TRANSPORTING NO FIELDS
         WITH TABLE KEY matnr = ls_stk-matnr charg = ls_stk-charg.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

    CLEAR ls_out.
    ls_out-matnr   = ls_stk-matnr.
    ls_out-charg   = ls_stk-charg.
    ls_out-xchpf   = ls_stk-xchpf.
    ls_out-qty_sap = ls_stk-menge.
    ls_out-meins   = ls_stk-meins.

    IF lcl_help=>seg_exists( iv_matnr = ls_stk-matnr
                             iv_bwkey = p_wdst ) = abap_true.
*     inconsistency: stock exists in SAP, valuation segment already in
*     target plant, but the record is missing from the input file.
      ls_out-status  = gc_st_incons.
      ls_out-message = 'Inconsistency: SAP stock not in input file but '
                    && 'valuation segment exists in target plant'.
      PERFORM f_add_log USING gc_msgid '010' 'E' CHANGING ls_out.
    ELSE.
*     not in file and no segment -> nothing to migrate; informational.
      ls_out-status  = gc_st_skip.
      ls_out-message = 'SAP stock not in input file (no target segment) '
                    && '- not processed'.
      PERFORM f_add_log USING gc_msgid '011' 'W' CHANGING ls_out.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PROCESS_LINES   (3.2 - 3.6 per input line)
*&---------------------------------------------------------------------*
FORM f_process_lines.

  DATA: ls_raw   TYPE ty_input_raw,
        ls_stk   TYPE ty_stock,
        ls_sum   TYPE ty_input_sum,
        ls_out   TYPE ty_out,
        lt_alloc TYPE tt_alloc,
        ls_alloc TYPE ty_alloc,
        lv_avail TYPE menge_d,
        lv_aok   TYPE abap_bool,
        lv_full  TYPE abap_bool,
        lv_found TYPE abap_bool,
        lv_mblnr TYPE mblnr,
        lv_mjahr TYPE mjahr,
        lv_msg   TYPE bapi_msg,
        lv_id    TYPE symsgid,
        lv_no    TYPE symsgno,
        lv_ty    TYPE symsgty,
        lv_split TYPE abap_bool,
        lv_vt    TYPE bwtar_d,
        lv_cerr  TYPE abap_bool,
        lv_cmsg  TYPE bapi_msg.

* memorised batch-extension result per MATNR + CHARG          [v0.2 - 6]
  DATA: lt_done TYPE tt_done,
        ls_done TYPE ty_done.

  lv_full = COND #( WHEN gv_run_mode = gc_mode_full THEN abap_true
                                                     ELSE abap_false ).

  LOOP AT gt_input_raw INTO ls_raw.

    CLEAR: ls_out, lt_alloc, lv_mblnr, lv_mjahr, lv_msg, lv_id, lv_no, lv_ty,
           lv_avail, lv_aok, lv_found, lv_split, lv_vt, lv_cerr, lv_cmsg.
    ls_out-matnr     = ls_raw-matnr.
    ls_out-charg     = ls_raw-charg.
    ls_out-bwtar     = ls_raw-bwtar.
    ls_out-qty_input = ls_raw-menge.
    ls_out-meins     = ls_raw-meins.
    ls_out-normbat   = ls_raw-norm.

*   --- NO_BATCH declaration contradicted by the material master -----
    IF ls_raw-bad = abap_true.
      ls_out-status  = gc_st_err.
      ls_out-message = ls_raw-badtx.
      PERFORM f_add_log USING gc_msgid ls_raw-badno 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

*   batch flag + SAP stock for this material/batch
    READ TABLE gt_stock INTO ls_stk
         WITH KEY matnr = ls_raw-matnr charg = ls_raw-charg.
    IF sy-subrc = 0.
      lv_found       = abap_true.
      ls_out-xchpf   = ls_stk-xchpf.
      ls_out-qty_sap = ls_stk-menge.
    ENDIF.

*   --- Zero-quantity rule (3.5): no movement ------------------------
    IF ls_raw-menge = 0.
      ls_out-status  = gc_st_zero.
      ls_out-message = 'Zero quantity in input file - no movement created'.
      PERFORM f_add_log USING gc_msgid '002' 'W' CHANGING ls_out.
      CONTINUE.
    ENDIF.

*   --- No unrestricted stock at all for this material/batch ---------
*   Reported explicitly instead of a misleading quantity mismatch and
*   applied in both modes: without stock there is nothing to issue.
    IF lv_found = abap_false.
      ls_out-status  = gc_st_err.
      ls_out-message = |No unrestricted stock in plant { p_wsrc } for material | &&
                       |{ ls_raw-matnr } batch { ls_raw-charg }|.
      PERFORM f_add_log USING gc_msgid '006' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.

*   ===== Full Validation Mode checks (bypassed in Direct mode) =====
    IF lv_full = abap_true.

*     3.3 valuation-type segment must exist in target plant
      IF lcl_help=>seg_exists( iv_matnr = ls_raw-matnr
                               iv_bwkey = p_wdst
                               iv_bwtar = ls_raw-bwtar ) = abap_false.
        ls_out-status  = gc_st_err.
        ls_out-message = |Valuation type { ls_raw-bwtar } not created in target plant { p_wdst }|.
        PERFORM f_add_log USING gc_msgid '003' 'E' CHANGING ls_out.
        CONTINUE.
      ENDIF.

*     3.5 quantity validation: file total = SAP unrestricted stock
      READ TABLE gt_input_sum INTO ls_sum
           WITH KEY matnr = ls_raw-matnr charg = ls_raw-charg.
      DATA(lv_var) = ls_sum-menge - ls_out-qty_sap.
      ls_out-variance = lv_var.
      IF lv_var <> 0.
        ls_out-status  = gc_st_err.
        ls_out-message = |Quantity mismatch: file { ls_sum-menge } vs SAP { ls_out-qty_sap } (var { lv_var })|.
        PERFORM f_add_log USING gc_msgid '004' 'E' CHANGING ls_out.
        CONTINUE.
      ENDIF.
    ENDIF.

*   --- Target valuation type                               [v0.3-18]
*   Posted only when the material is split-valuated in the target plant.
*   In Full Validation Mode this is guaranteed by the 3.3 check; in
*   Direct Transfer Mode a material without split valuation is posted
*   without valuation type.
    lv_split = lcl_help=>is_split_valuated( iv_matnr = ls_raw-matnr
                                            iv_bwkey = p_wdst ).
    lv_vt = COND #( WHEN lv_split = abap_true THEN ls_raw-bwtar ELSE space ).

*   Write the rows pending so far before any BAPI call: a ROLLBACK WORK
*   after a failed BAPI must not discard them.              [v0.3-20]
    PERFORM f_flush_logs CHANGING lv_cerr lv_cmsg.
    CLEAR: lv_cerr, lv_cmsg.

*   --- 3.4 Batch creation in target plant (batch-managed only) -------
*   No batch is created for a line declaring NO_BATCH: the material is
*   not batch-managed in either plant.                     [v0.2 - 11]
    IF ls_out-xchpf = gc_xchpf AND ls_raw-charg IS NOT INITIAL
                               AND ls_raw-nobat = abap_false.
      READ TABLE lt_done INTO ls_done
           WITH KEY matnr = ls_raw-matnr charg = ls_raw-charg.
      IF sy-subrc <> 0.
        CLEAR ls_done.
        ls_done-matnr = ls_raw-matnr.
        ls_done-charg = ls_raw-charg.
        PERFORM f_extend_batch USING ls_raw-matnr ls_raw-charg lv_vt
                               CHANGING ls_done-ok  ls_done-msg
                                        ls_done-id  ls_done-no ls_done-ty.
        INSERT ls_done INTO TABLE lt_done.
      ENDIF.
      IF ls_done-ok = abap_false.
        ls_out-status  = gc_st_err.
        ls_out-message = |Batch extension failed - transfer skipped. { ls_done-msg }|.
        PERFORM f_add_log USING ls_done-id ls_done-no ls_done-ty CHANGING ls_out.
        CONTINUE.
      ENDIF.
    ENDIF.

*   --- 3.6a Allocation of the issuing storage locations --------------
    PERFORM f_allocate_lgort USING ls_raw-matnr ls_raw-charg ls_raw-menge
                             CHANGING lt_alloc lv_aok lv_avail.
    IF lv_aok = abap_false.
      ls_out-status  = gc_st_err.
      ls_out-message = |Cannot allocate { ls_raw-menge } { ls_raw-meins } to storage | &&
                       |locations of plant { p_wsrc }: { lv_avail } still available|.
      PERFORM f_add_log USING gc_msgid '005' 'E' CHANGING ls_out.
      CONTINUE.
    ENDIF.
    PERFORM f_consume_alloc USING lt_alloc ls_raw-matnr ls_raw-charg gc_take.

*   --- 3.6b Post 301 (one document, one item per issuing LGORT) ------
    PERFORM f_post_301 USING ls_raw lt_alloc lv_vt
                       CHANGING lv_mblnr lv_mjahr lv_msg lv_id lv_no lv_ty.

    IF lv_mblnr IS NOT INITIAL.
      ls_out-status = COND #( WHEN p_test = abap_true THEN gc_st_test
                                                      ELSE gc_st_ok ).
      ls_out-mblnr  = lv_mblnr.
      ls_out-mjahr  = lv_mjahr.
      ls_out-message = COND #( WHEN p_test = abap_true
                               THEN 'Simulation OK - posting checked (TESTRUN), no document'
                               ELSE |Material document { lv_mblnr }/{ lv_mjahr }| ).
      IF lv_split = abap_false AND ls_raw-bwtar IS NOT INITIAL.
        ls_out-message = |{ ls_out-message } - no valuation type: material not | &&
                         |split-valuated in plant { p_wdst }|.
      ENDIF.
    ELSE.
      ls_out-status  = gc_st_err.
      ls_out-message = lv_msg.
*     posting failed: the stock is available again for another line
      PERFORM f_consume_alloc USING lt_alloc ls_raw-matnr ls_raw-charg gc_back.
    ENDIF.

*   one log row per issuing storage location
    LOOP AT lt_alloc INTO ls_alloc.
      ls_out-lgort_src  = ls_alloc-lgort.
      ls_out-menge_post = ls_alloc-menge.
      PERFORM f_add_log USING lv_id lv_no lv_ty CHANGING ls_out.
    ENDLOOP.

*   Commit: the posting (update task) and its log rows in one LUW, so a
*   posted document can never lack its log.                 [v0.3-20]
    PERFORM f_flush_logs CHANGING lv_cerr lv_cmsg.

*   The update task can still fail after the commit: the document does
*   not exist, and the log says so.
    IF lv_cerr = abap_true AND p_test = abap_false AND lv_mblnr IS NOT INITIAL.
      DATA(lv_utxt) = CONV natxt( |Update failed after commit - document | &&
                                  |{ lv_mblnr } not posted. { lv_cmsg }| ).
      UPDATE zlot_mov_exec
         SET status = @gc_st_err, msgty = 'E', msgid = @gc_msgid,
             msgno  = '022', msgtx = @lv_utxt
       WHERE run_id  = @gv_run_id
         AND run_seq = @gv_run_seq
         AND mblnr   = @lv_mblnr
         AND mjahr   = @lv_mjahr.
      COMMIT WORK.
      LOOP AT gt_out ASSIGNING FIELD-SYMBOL(<ls_upd>)
           WHERE mblnr = lv_mblnr AND mjahr = lv_mjahr.
        <ls_upd>-status  = gc_st_err.
        <ls_upd>-msgty   = 'E'.
        <ls_upd>-msgid   = gc_msgid.
        <ls_upd>-msgno   = '022'.
        <ls_upd>-message = lv_utxt.
      ENDLOOP.
      PERFORM f_consume_alloc USING lt_alloc ls_raw-matnr ls_raw-charg gc_back.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_EXTEND_BATCH   (3.4 BAPI_BATCH_CREATE + COMMIT)
*&      Plant-level batch existence and valuation type read from MCHA.
*&      The new batch takes the attributes of the source batch (expiry
*&      date, production date, vendor batch, ...) and the target
*&      valuation type.                                    [v0.3-16, 17]
*&      Classification is not copied here: verify in the sandbox whether
*&      it is held at batch level above plant (shared) or must be passed
*&      in the CLASS* tables of BAPI_BATCH_CREATE.
*&---------------------------------------------------------------------*
FORM f_extend_batch USING iv_matnr TYPE matnr
                          iv_charg TYPE charg_d
                          iv_bwtar TYPE bwtar_d
                    CHANGING cv_ok  TYPE abap_bool
                             cv_msg TYPE bapi_msg
                             cv_id  TYPE symsgid
                             cv_no  TYPE symsgno
                             cv_ty  TYPE symsgty.

  DATA: ls_att  TYPE bapibatchatt,
        lt_ret  TYPE STANDARD TABLE OF bapiret2,
        ls_ret  TYPE bapiret2,
        lv_newb TYPE charg_d.

  CLEAR: cv_ok, cv_msg, cv_id, cv_no, cv_ty.

* already in target plant? Its valuation type must be the one of the
* file: a batch carries a single valuation type.           [v0.3-16]
  SELECT SINGLE charg, bwtar FROM mcha INTO @DATA(ls_mcha)
    WHERE matnr = @iv_matnr AND werks = @p_wdst AND charg = @iv_charg.
  IF sy-subrc = 0.
    IF iv_bwtar IS NOT INITIAL AND ls_mcha-bwtar IS NOT INITIAL
                               AND ls_mcha-bwtar <> iv_bwtar.
      cv_ok  = abap_false.
      cv_id  = gc_msgid. cv_no = '019'. cv_ty = 'E'.
      cv_msg = |Batch { iv_charg } exists in plant { p_wdst } with valuation type | &&
               |{ ls_mcha-bwtar }, file gives { iv_bwtar }|.
      PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_err abap_true
                                  cv_ty cv_id cv_no cv_msg.
      RETURN.
    ENDIF.
    cv_ok  = abap_true.
    cv_msg = 'Batch already exists in target plant'.
    PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_ok abap_true
                                'S' space space cv_msg.
    RETURN.
  ENDIF.

* attributes of the source batch                          [v0.3-17]
  CALL FUNCTION 'BAPI_BATCH_GET_DETAIL'
    EXPORTING material        = iv_matnr
              batch           = iv_charg
              plant           = p_wsrc
    IMPORTING batchattributes = ls_att
    TABLES    return          = lt_ret.
  LOOP AT lt_ret INTO ls_ret WHERE type CA 'EA'.
    EXIT.
  ENDLOOP.
  IF sy-subrc = 0.
    cv_ok  = abap_false.
    cv_id  = gc_msgid. cv_no = '020'. cv_ty = 'E'.
    cv_msg = |Source batch { iv_charg } cannot be read in plant { p_wsrc }: { ls_ret-message }|.
    PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_err space
                                cv_ty cv_id cv_no cv_msg.
    RETURN.
  ENDIF.
  ls_att-val_type = iv_bwtar.        " target valuation type (blank if none)

  IF p_test = abap_true.
    cv_ok  = abap_true.                        " assume creatable in sim
    cv_msg = 'Simulation: batch would be extended to target plant'.
    PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_test space
                                space space space cv_msg.
    RETURN.
  ENDIF.

  CLEAR lt_ret.
  CALL FUNCTION 'BAPI_BATCH_CREATE'
    EXPORTING material        = iv_matnr
              batch           = iv_charg
              plant           = p_wdst
              batchattributes = ls_att
    IMPORTING batch           = lv_newb
    TABLES    return          = lt_ret.

  LOOP AT lt_ret INTO ls_ret WHERE type CA 'EA'.
    EXIT.
  ENDLOOP.
  IF sy-subrc = 0.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    cv_ok = abap_false.
    cv_id = ls_ret-id. cv_no = ls_ret-number. cv_ty = ls_ret-type.
    cv_msg = ls_ret-message.
    PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_err space
                                ls_ret-type ls_ret-id ls_ret-number cv_msg.
  ELSE.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = abap_true.
    cv_ok  = abap_true.
    cv_msg = 'Batch extended to target plant (source batch attributes copied)'.
    PERFORM f_add_ext_log USING iv_matnr iv_charg gc_st_ok space
                                'S' space space cv_msg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_POST_301   (3.6 BAPI_GOODSMVT_CREATE)
*&      One material document per input line, one ITEM per issuing
*&      storage location. STGE_LOC = issuing location from the
*&      allocation, MOVE_STLOC = P_LGDST.                     [v0.2 - 1]
*&      The target valuation type goes in MOVE_VAL_TYPE (receiving
*&      side); VAL_TYPE (issuing side) stays blank.          [v0.3-15]
*&      No COMMIT here: the caller writes the log rows and commits them
*&      with the document (F_FLUSH_LOGS).                    [v0.3-20]
*&      Simulation: the BAPI runs with TESTRUN = 'X', then rollback.
*&                                                           [v0.3-21]
*&---------------------------------------------------------------------*
FORM f_post_301 USING is_raw   TYPE ty_input_raw
                      it_alloc TYPE tt_alloc
                      iv_bwtar TYPE bwtar_d
                CHANGING cv_mblnr TYPE mblnr
                         cv_mjahr TYPE mjahr
                         cv_msg   TYPE bapi_msg
                         cv_id    TYPE symsgid
                         cv_no    TYPE symsgno
                         cv_ty    TYPE symsgty.

  DATA: ls_head  TYPE bapi2017_gm_head_01,
        ls_code  TYPE bapi2017_gm_code,
        lt_item  TYPE STANDARD TABLE OF bapi2017_gm_item_create,
        ls_item  TYPE bapi2017_gm_item_create,
        ls_alloc TYPE ty_alloc,
        lt_ret   TYPE STANDARD TABLE OF bapiret2,
        ls_ret   TYPE bapiret2,
        lv_doc   TYPE bapi2017_gm_head_ret-mat_doc,
        lv_year  TYPE bapi2017_gm_head_ret-doc_year.

  CLEAR: cv_mblnr, cv_mjahr, cv_msg, cv_id, cv_no, cv_ty.

  ls_head-pstng_date = p_budat.
  ls_head-doc_date   = sy-datum.
  ls_head-header_txt = 'HBM Split Val Ph1'.
  ls_code-gm_code    = gc_gm_code.

  LOOP AT it_alloc INTO ls_alloc.
    CLEAR ls_item.
    ls_item-material   = is_raw-matnr.
    ls_item-plant      = p_wsrc.
    ls_item-stge_loc   = ls_alloc-lgort.      " issuing storage location
    ls_item-move_type  = gc_mov_type.
    ls_item-entry_qnt  = ls_alloc-menge.
    ls_item-entry_uom  = is_raw-meins.
    ls_item-move_plant = p_wdst.
    ls_item-move_stloc = p_lgdst.             " receiving storage location
*   receiving valuation type; the issuing side (VAL_TYPE) stays blank,
*   the source plant is not split-valuated              [v0.3-15, 18]
    ls_item-move_val_type = iv_bwtar.
*   The batch is passed only when the material is batch-managed. For a
*   line declaring NO_BATCH the receiving side carries the valuation
*   type alone, with no batch on either side.              [v0.2 - 11]
    IF is_raw-charg IS NOT INITIAL AND is_raw-nobat = abap_false.
      ls_item-batch      = is_raw-charg.
      ls_item-move_batch = is_raw-charg.
    ENDIF.
    APPEND ls_item TO lt_item.
  ENDLOOP.

  IF lt_item IS INITIAL.
    cv_msg = 'No storage location allocated - nothing posted'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
    EXPORTING goodsmvt_header = ls_head
              goodsmvt_code   = ls_code
              testrun         = p_test               " [v0.3-21]
    IMPORTING materialdocument = lv_doc
              matdocumentyear  = lv_year
    TABLES    goodsmvt_item    = lt_item
              return           = lt_ret.

  READ TABLE lt_ret INTO ls_ret WITH KEY type = 'E'.
  IF sy-subrc <> 0.
    READ TABLE lt_ret INTO ls_ret WITH KEY type = 'A'.
  ENDIF.
  IF sy-subrc = 0.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    cv_id = ls_ret-id. cv_no = ls_ret-number. cv_ty = ls_ret-type.
    cv_msg = ls_ret-message.
  ELSEIF p_test = abap_true.
*   the check passed; nothing may remain of the test run
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    cv_mblnr = 'SIMULATED'.
    cv_mjahr = p_budat(4).
  ELSE.
*   posted in the update task at the caller's commit      [v0.3-20]
    cv_mblnr = lv_doc.
    cv_mjahr = lv_year.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_ADD_LOG   (buffer one ZLOT_MOV_EXEC row + ALV row)
*&      Stamps the run context on the output row, so the ALV mirrors
*&      ZLOT_MOV_EXEC as specified in FSD 4.4.2.              [v0.2 - 9]
*&---------------------------------------------------------------------*
FORM f_add_log USING iv_id  TYPE symsgid
                     iv_no  TYPE symsgno
                     iv_ty  TYPE symsgty
               CHANGING cs_out TYPE ty_out.

  DATA ls_log TYPE zlot_mov_exec.

  ADD 1 TO gv_posnr.

* make the normalisation visible on the record itself, once
  IF cs_out-normbat = abap_true AND cs_out-message NS 'normalised'.
    cs_out-message = |{ cs_out-message } (batch value normalised to blank)|.
  ENDIF.

* run context on the output row
  cs_out-run_id    = gv_run_id.
  cs_out-run_seq   = gv_run_seq.
  cs_out-run_mode  = gv_run_mode.
  cs_out-testrun   = p_test.
  cs_out-werks_src = p_wsrc.
  cs_out-werks_dst = p_wdst.
  cs_out-lgort_dst = p_lgdst.
  cs_out-msgty     = iv_ty.
  cs_out-msgid     = iv_id.
  cs_out-msgno     = iv_no.

  ls_log-run_id    = gv_run_id.
  ls_log-run_seq   = gv_run_seq.
  ls_log-posnr     = gv_posnr.
  ls_log-run_mode  = gv_run_mode.
  ls_log-testrun   = p_test.
  ls_log-matnr     = cs_out-matnr.
  ls_log-charg     = cs_out-charg.
  ls_log-xchpf     = cs_out-xchpf.
  ls_log-bwtar     = cs_out-bwtar.
  ls_log-werks_src = p_wsrc.
  ls_log-werks_dst = p_wdst.
  ls_log-lgort_src = cs_out-lgort_src.
  ls_log-lgort_dst = p_lgdst.
  ls_log-bwart     = gc_mov_type.
  ls_log-budat     = p_budat.
  ls_log-menge     = COND #( WHEN cs_out-menge_post IS NOT INITIAL
                             THEN cs_out-menge_post ELSE cs_out-qty_input ).
  ls_log-meins     = cs_out-meins.
  ls_log-stock_sap = cs_out-qty_sap.
  ls_log-qty_input = cs_out-qty_input.
  ls_log-variance  = cs_out-variance.
  ls_log-status    = cs_out-status.
  ls_log-mblnr     = cs_out-mblnr.
  ls_log-mjahr     = cs_out-mjahr.
  ls_log-msgty     = iv_ty.
  ls_log-msgid     = iv_id.
  ls_log-msgno     = iv_no.
  ls_log-msgtx     = cs_out-message.
  ls_log-ernam     = sy-uname.
  ls_log-erdat     = sy-datum.
  ls_log-erzet     = sy-uzeit.
  APPEND ls_log TO gt_mov_log.

  APPEND cs_out TO gt_out.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_ADD_EXT_LOG   (buffer one ZLOT_BATCH_EXT row)
*&---------------------------------------------------------------------*
FORM f_add_ext_log USING iv_matnr TYPE matnr
                         iv_charg TYPE charg_d
                         iv_stat  TYPE c
                         iv_exist TYPE abap_bool
                         iv_ty    TYPE symsgty
                         iv_id    TYPE symsgid
                         iv_no    TYPE symsgno
                         iv_txt   TYPE bapi_msg.
  DATA ls_log TYPE zlot_batch_ext.
  ls_log-run_id        = gv_run_id.
  ls_log-run_seq       = gv_run_seq.
  ls_log-matnr         = iv_matnr.
  ls_log-charg         = iv_charg.
  ls_log-werks_dst     = p_wdst.
  ls_log-status        = iv_stat.
  ls_log-already_exist = iv_exist.
  ls_log-msgty         = iv_ty.
  ls_log-msgid         = iv_id.
  ls_log-msgno         = iv_no.
  ls_log-msgtx         = iv_txt.
  ls_log-ernam         = sy-uname.
  ls_log-erdat         = sy-datum.
  ls_log-erzet         = sy-uzeit.
  APPEND ls_log TO gt_ext_log.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_SAVE_LOGS
*&---------------------------------------------------------------------*
FORM f_save_logs.
  DATA: lv_err TYPE abap_bool,
        lv_msg TYPE bapi_msg.
  PERFORM f_flush_logs CHANGING lv_err lv_msg.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_FLUSH_LOGS                                    [v0.3-20]
*&      Writes the buffered log rows and commits. Called before every
*&      BAPI call (so that a rollback cannot discard them) and right
*&      after a posting (so that the document and its log rows share one
*&      LUW). CV_ERR reports an update-task failure returned by the
*&      commit.
*&---------------------------------------------------------------------*
FORM f_flush_logs CHANGING cv_err TYPE abap_bool
                           cv_msg TYPE bapi_msg.

  DATA: ls_ret TYPE bapiret2,
        lv_n   TYPE i,
        lv_txt TYPE string.

  CLEAR: cv_err, cv_msg.

  IF gt_ext_log IS INITIAL AND gt_mov_log IS INITIAL.
    RETURN.
  ENDIF.

  IF gt_ext_log IS NOT INITIAL.
    lv_n = lines( gt_ext_log ).
    INSERT zlot_batch_ext FROM TABLE gt_ext_log ACCEPTING DUPLICATE KEYS.
    IF sy-dbcnt <> lv_n.
      lv_txt = |ZLOT_BATCH_EXT: { lv_n - sy-dbcnt } log row(s) not written (duplicate key)|.
      WRITE: / lv_txt COLOR COL_NEGATIVE.
    ENDIF.
    CLEAR gt_ext_log.
  ENDIF.

  IF gt_mov_log IS NOT INITIAL.
    lv_n = lines( gt_mov_log ).
    INSERT zlot_mov_exec FROM TABLE gt_mov_log ACCEPTING DUPLICATE KEYS.
    IF sy-dbcnt <> lv_n.
      lv_txt = |ZLOT_MOV_EXEC: { lv_n - sy-dbcnt } log row(s) not written (duplicate key)|.
      WRITE: / lv_txt COLOR COL_NEGATIVE.
    ENDIF.
    CLEAR gt_mov_log.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING wait   = abap_true
    IMPORTING return = ls_ret.
  IF ls_ret-type CA 'EA'.
    cv_err = abap_true.
    cv_msg = ls_ret-message.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DISPLAY_ALV
*&---------------------------------------------------------------------*
FORM f_display_alv.
  DATA: lt_fcat TYPE slis_t_fieldcat_alv,
        ls_fcat TYPE slis_fieldcat_alv,
        ls_lay  TYPE slis_layout_alv.
  DEFINE add_col.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1. ls_fcat-seltext_l = &2.
    ls_fcat-seltext_m = &2. ls_fcat-seltext_s = &2.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.
  add_col 'STATUS'     'Status'.
  add_col 'MATNR'      'Material'.
  add_col 'CHARG'      'Batch'.
  add_col 'XCHPF'      'BatchMgd'.
  add_col 'BWTAR'      'Val.Type'.
  add_col 'WERKS_SRC'  'Src Plant'.
  add_col 'LGORT_SRC'  'Src SLoc'.
  add_col 'WERKS_DST'  'Dst Plant'.
  add_col 'LGORT_DST'  'Dst SLoc'.
  add_col 'MENGE_POST' 'Qty Posted'.
  add_col 'MEINS'      'UoM'.
  add_col 'QTY_INPUT'  'File Qty'.
  add_col 'QTY_SAP'    'SAP Stock'.
  add_col 'VARIANCE'   'Variance'.
  add_col 'MBLNR'      'Mat.Doc'.
  add_col 'MJAHR'      'Year'.
  add_col 'MSGID'      'Msg Class'.
  add_col 'MSGNO'      'Msg No'.
  add_col 'MESSAGE'    'Message'.
  add_col 'RUN_ID'     'RUN_ID'.
  add_col 'RUN_SEQ'    'Seq'.
  add_col 'RUN_MODE'   'Mode'.
  add_col 'TESTRUN'    'Simulation'.
  ls_lay-colwidth_optimize = abap_true.
  ls_lay-zebra = abap_true.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING i_callback_program = sy-repid
              is_layout   = ls_lay
              it_fieldcat = lt_fcat
    TABLES    t_outtab    = gt_out
    EXCEPTIONS program_error = 1 OTHERS = 2.
ENDFORM.
