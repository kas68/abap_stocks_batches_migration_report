*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_BATCH_COPY
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of batch master data from the source plant to the
*&           target plant, enriched with the valuation type of a file
*& Version : v0.1
*& Package : ZPTP_SPLIT_VAL
*&
*&---------------------------------------------------------------------*
*& Description
*&---------------------------------------------------------------------*
*& Reads an Excel file (.xlsx) made of one header row and several item
*& rows:
*&
*&     column A  material number
*&     column B  batch
*&     column C  valuation type
*&
*& For every item the report reads the batch data at plant level in the
*& source plant (default 8P01, BAPI_BATCH_GET_DETAIL) and creates the
*& batch record at plant level in the target plant (default 8Q01,
*& BAPI_BATCH_CREATE) with the same attributes, the valuation type being
*& the one of the file. No stock movement is posted.
*&
*& Checks per item (the item is rejected with status E otherwise):
*&   - the three columns are filled, the material number is convertible;
*&   - the material is extended to both plants and is batch-managed in
*&     both (MARC-XCHPF or MARA-XCHPF);
*&   - the valuation type exists in the target plant (MBEW-BWTAR);
*&   - the source batch exists in the source plant;
*&   - a batch already existing in the target plant is not recreated:
*&     status S if its valuation type is the one of the file, E if not
*&     (a batch carries one valuation type);
*&   - the same Material + Batch twice in the file with two different
*&     valuation types: every occurrence is rejected.
*&
*& Test run (P_TEST, default on): all checks run, no batch is created.
*& The file is read from the PC (dialog) or from the application server
*& (dialog and background). Result: ALV list, no database log.
*&
*&---------------------------------------------------------------------*
*& Assumptions
*&---------------------------------------------------------------------*
*& - The first worksheet is read; line 1 is the header and is skipped.
*& - Material number and batch cells are formatted as text in Excel
*&   (leading zeros, numeric-looking batches are not altered).
*& - Valuation level = plant (MBEW-BWKEY = target plant).
*& - Classification of the batch is not copied (as in ZPTP_SPLIT_VAL_MIG).
*&
*&---------------------------------------------------------------------*
*& Related developments
*&---------------------------------------------------------------------*
*& ZPTP_SPLIT_VAL_MIG (same batch creation logic, F_EXTEND_BATCH).
*&---------------------------------------------------------------------*
REPORT zptp_split_val_batch_copy LINE-SIZE 200.

TYPE-POOLS: abap, slis.

CONSTANTS:
  gc_st_ok   TYPE c VALUE 'S',      " batch created / already in target plant
  gc_st_err  TYPE c VALUE 'E',
  gc_st_test TYPE c VALUE 'T',      " simulation, not created
  gc_xchpf   TYPE xchpf VALUE 'X'.

TYPES: BEGIN OF gty_item,
         line  TYPE i,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
         bad   TYPE abap_bool,
         msg   TYPE bapi_msg,
       END OF gty_item,
       gtt_item TYPE STANDARD TABLE OF gty_item WITH DEFAULT KEY.

TYPES: BEGIN OF gty_out,
         status  TYPE c LENGTH 1,
         line    TYPE i,
         matnr   TYPE matnr,
         charg   TYPE charg_d,
         bwtar   TYPE bwtar_d,
         message TYPE bapi_msg,
       END OF gty_out,
       gtt_out TYPE STANDARD TABLE OF gty_out WITH DEFAULT KEY.

TYPES: BEGIN OF gty_marc,
         matnr    TYPE matnr,
         werks    TYPE werks_d,
         batchmgd TYPE abap_bool,
       END OF gty_marc,
       gtt_marc TYPE SORTED TABLE OF gty_marc WITH UNIQUE KEY matnr werks.

DATA: gt_item TYPE gtt_item,
      gt_out  TYPE gtt_out,
      gt_marc TYPE gtt_marc.

*&---------------------------------------------------------------------*
*&  Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  PARAMETERS: p_wsrc TYPE werks_d OBLIGATORY DEFAULT '8P01',       " source plant
              p_wdst TYPE werks_d OBLIGATORY DEFAULT '8Q01'.       " target plant
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_loc TYPE abap_bool RADIOBUTTON GROUP src DEFAULT 'X' USER-COMMAND src, " PC
              p_srv TYPE abap_bool RADIOBUTTON GROUP src.                              " server
  PARAMETERS: p_file TYPE string LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X'.       " simulation
SELECTION-SCREEN END OF BLOCK b3.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f_f4_file.

AT SELECTION-SCREEN.
  PERFORM f_check_screen.

START-OF-SELECTION.
  PERFORM f_read_file.
  PERFORM f_read_marc.
  PERFORM f_check_items.
  PERFORM f_process_items.

END-OF-SELECTION.
  PERFORM f_display_alv.

*&---------------------------------------------------------------------*
FORM f_f4_file.
  DATA: lt_ftab TYPE filetable,
        lv_rc   TYPE i,
        lv_usr  TYPE i.
  IF p_srv = abap_true.
    RETURN.                              " type the server path
  ENDIF.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING window_title = 'Select the Excel file'
              file_filter  = 'Excel (*.xlsx)|*.xlsx'
    CHANGING  file_table   = lt_ftab
              rc           = lv_rc
              user_action  = lv_usr
    EXCEPTIONS OTHERS      = 1 ).
  IF sy-subrc = 0 AND lv_usr = cl_gui_frontend_services=>action_ok.
    READ TABLE lt_ftab INDEX 1 INTO DATA(ls_ftab).
    IF sy-subrc = 0.
      p_file = ls_ftab-filename.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_check_screen.
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
  IF p_wsrc = p_wdst.
    MESSAGE 'Source and target plant must be different' TYPE 'E'.
  ENDIF.
  SELECT SINGLE werks FROM t001w INTO @DATA(lv_w) WHERE werks = @p_wsrc.
  IF sy-subrc <> 0.
    MESSAGE |Source plant { p_wsrc } does not exist (T001W)| TYPE 'E'.
  ENDIF.
  SELECT SINGLE werks FROM t001w INTO @lv_w WHERE werks = @p_wdst.
  IF sy-subrc <> 0.
    MESSAGE |Target plant { p_wdst } does not exist (T001W)| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_FILE   (xlsx from PC or application server)
*&---------------------------------------------------------------------*
FORM f_read_file.

  DATA: lt_bin   TYPE STANDARD TABLE OF x255,
        lv_len   TYPE i,
        lv_xstr  TYPE xstring,
        lv_chunk TYPE x255,
        lo_xl    TYPE REF TO cl_fdt_xl_spreadsheet,
        lt_names TYPE if_fdt_doc_spreadsheet=>t_worksheet_names,
        lo_data  TYPE REF TO data,
        ls_item  TYPE gty_item,
        lv_matnr TYPE string,
        lv_charg TYPE string,
        lv_bwtar TYPE string,
        lv_row   TYPE i.
  FIELD-SYMBOLS: <lt_data> TYPE STANDARD TABLE,
                 <ls_row>  TYPE any,
                 <lv_cell> TYPE any.

* --- file content as xstring ------------------------------------------
  IF p_srv = abap_true.
    OPEN DATASET p_file FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      MESSAGE |Cannot open file on the application server: { p_file }| TYPE 'E'.
    ENDIF.
    DO.
      READ DATASET p_file INTO lv_chunk ACTUAL LENGTH lv_len.
      IF lv_len > 0.
        CONCATENATE lv_xstr lv_chunk(lv_len) INTO lv_xstr IN BYTE MODE.
      ENDIF.
      IF sy-subrc <> 0. EXIT. ENDIF.
    ENDDO.
    CLOSE DATASET p_file.
  ELSE.
    cl_gui_frontend_services=>gui_upload(
      EXPORTING filename   = p_file
                filetype   = 'BIN'
      IMPORTING filelength = lv_len
      CHANGING  data_tab   = lt_bin
      EXCEPTIONS OTHERS    = 1 ).
    IF sy-subrc <> 0.
      MESSAGE |Cannot read local file { p_file } (rc={ sy-subrc })| TYPE 'E'.
    ENDIF.
    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING input_length = lv_len
      IMPORTING buffer       = lv_xstr
      TABLES    binary_tab   = lt_bin
      EXCEPTIONS failed      = 1 OTHERS = 2.
    IF sy-subrc <> 0.
      MESSAGE 'Cannot convert the file content' TYPE 'E'.
    ENDIF.
  ENDIF.
  IF lv_xstr IS INITIAL.
    MESSAGE |File { p_file } is empty| TYPE 'E'.
  ENDIF.

* --- first worksheet ----------------------------------------------------
  TRY.
      lo_xl = NEW cl_fdt_xl_spreadsheet( document_name = p_file
                                         xdocument     = lv_xstr ).
      lo_xl->if_fdt_doc_spreadsheet~get_worksheet_names(
        IMPORTING worksheet_names = lt_names ).
      READ TABLE lt_names INDEX 1 INTO DATA(lv_sheet).
      IF sy-subrc <> 0.
        MESSAGE 'The Excel file has no worksheet' TYPE 'E'.
      ENDIF.
      lo_data = lo_xl->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lv_sheet ).
    CATCH cx_fdt_excel_core INTO DATA(lx_xl).
      MESSAGE |Cannot read the Excel file (.xlsx expected): { lx_xl->get_text( ) }| TYPE 'E'.
  ENDTRY.
  ASSIGN lo_data->* TO <lt_data>.

* --- items: row 1 = header ----------------------------------------------
  LOOP AT <lt_data> ASSIGNING <ls_row>.
    lv_row = sy-tabix.
    IF lv_row = 1.
      CONTINUE.
    ENDIF.
    CLEAR: ls_item, lv_matnr, lv_charg, lv_bwtar.
    ASSIGN COMPONENT 1 OF STRUCTURE <ls_row> TO <lv_cell>.
    IF sy-subrc = 0. lv_matnr = <lv_cell>. ENDIF.
    ASSIGN COMPONENT 2 OF STRUCTURE <ls_row> TO <lv_cell>.
    IF sy-subrc = 0. lv_charg = <lv_cell>. ENDIF.
    ASSIGN COMPONENT 3 OF STRUCTURE <ls_row> TO <lv_cell>.
    IF sy-subrc = 0. lv_bwtar = <lv_cell>. ENDIF.
    CONDENSE: lv_matnr, lv_charg, lv_bwtar.
    IF lv_matnr IS INITIAL AND lv_charg IS INITIAL AND lv_bwtar IS INITIAL.
      CONTINUE.                           " empty row
    ENDIF.

    ls_item-line  = lv_row.
    ls_item-charg = to_upper( lv_charg ).
    ls_item-bwtar = to_upper( lv_bwtar ).
    IF lv_matnr IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING  input        = lv_matnr
        IMPORTING  output       = ls_item-matnr
        EXCEPTIONS length_error = 1
                   OTHERS       = 2.
      IF sy-subrc <> 0.
        ls_item-bad = abap_true.
        ls_item-msg = |Line { lv_row }: material number '{ lv_matnr }' cannot be converted|.
      ENDIF.
    ENDIF.
    APPEND ls_item TO gt_item.
  ENDLOOP.

  IF gt_item IS INITIAL.
    MESSAGE 'No item found in the file (line 1 is the header)' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_read_marc.
  DATA lt_mat TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line.
  LOOP AT gt_item INTO DATA(ls_item) WHERE matnr IS NOT INITIAL.
    INSERT ls_item-matnr INTO TABLE lt_mat.
  ENDLOOP.
  IF lt_mat IS INITIAL.
    RETURN.
  ENDIF.
  SELECT c~matnr, c~werks, c~xchpf, a~xchpf AS xchpf_cl
    INTO TABLE @DATA(lt_marc)
    FROM marc AS c
    INNER JOIN mara AS a ON a~matnr = c~matnr
    FOR ALL ENTRIES IN @lt_mat
    WHERE c~matnr = @lt_mat-table_line
      AND ( c~werks = @p_wsrc OR c~werks = @p_wdst ).
  LOOP AT lt_marc INTO DATA(ls_m).
    INSERT VALUE gty_marc( matnr    = ls_m-matnr
                           werks    = ls_m-werks
                           batchmgd = xsdbool( ls_m-xchpf = gc_xchpf
                                            OR ls_m-xchpf_cl = gc_xchpf ) )
           INTO TABLE gt_marc.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_CHECK_ITEMS   (file-level checks, before any creation)
*&---------------------------------------------------------------------*
FORM f_check_items.

  TYPES: BEGIN OF lty_key,
           matnr TYPE matnr,
           charg TYPE charg_d,
           bwtar TYPE bwtar_d,
         END OF lty_key.
  DATA: lt_seen  TYPE SORTED TABLE OF lty_key WITH UNIQUE KEY matnr charg bwtar,
        lt_multi TYPE SORTED TABLE OF lty_key WITH UNIQUE KEY matnr charg bwtar,
        ls_src   TYPE gty_marc,
        ls_dst   TYPE gty_marc,
        ls_prev  TYPE lty_key.

* --- several valuation types for one batch ----------------------------
  LOOP AT gt_item INTO DATA(ls_i) WHERE bad = abap_false
                                    AND matnr IS NOT INITIAL AND charg IS NOT INITIAL.
    INSERT VALUE lty_key( matnr = ls_i-matnr charg = ls_i-charg bwtar = ls_i-bwtar )
           INTO TABLE lt_seen.
  ENDLOOP.
  LOOP AT lt_seen INTO DATA(ls_s).
    IF ls_s-matnr = ls_prev-matnr AND ls_s-charg = ls_prev-charg.
      INSERT VALUE lty_key( matnr = ls_s-matnr charg = ls_s-charg ) INTO TABLE lt_multi.
    ENDIF.
    ls_prev = ls_s.
  ENDLOOP.

* --- valuation types of the target plant (read once) -------------------
  SELECT matnr, bwtar FROM mbew INTO TABLE @DATA(lt_mbew)
    WHERE bwkey = @p_wdst AND bwtar <> @space.
  SORT lt_mbew BY matnr bwtar.

  LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<ls_item>) WHERE bad = abap_false.

    IF <ls_item>-matnr IS INITIAL OR <ls_item>-charg IS INITIAL OR <ls_item>-bwtar IS INITIAL.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Line { <ls_item>-line }: material, batch and valuation type are all mandatory|.
      CONTINUE.
    ENDIF.

    READ TABLE gt_marc INTO ls_src
         WITH TABLE KEY matnr = <ls_item>-matnr werks = p_wsrc.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr } is not extended to plant { p_wsrc }|.
      CONTINUE.
    ENDIF.
    READ TABLE gt_marc INTO ls_dst
         WITH TABLE KEY matnr = <ls_item>-matnr werks = p_wdst.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr } is not extended to plant { p_wdst }|.
      CONTINUE.
    ENDIF.
    IF ls_src-batchmgd = abap_false OR ls_dst-batchmgd = abap_false.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr } is not batch-managed in both plants|.
      CONTINUE.
    ENDIF.

    READ TABLE lt_mbew TRANSPORTING NO FIELDS
         WITH KEY matnr = <ls_item>-matnr bwtar = <ls_item>-bwtar BINARY SEARCH.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Valuation type { <ls_item>-bwtar } does not exist for material | &&
                      |{ <ls_item>-matnr } in plant { p_wdst }|.
      CONTINUE.
    ENDIF.

    LOOP AT lt_multi TRANSPORTING NO FIELDS
         WHERE matnr = <ls_item>-matnr AND charg = <ls_item>-charg.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Batch { <ls_item>-charg } of material { <ls_item>-matnr } is given | &&
                      |with several valuation types in the file - rejected|.
      EXIT.
    ENDLOOP.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PROCESS_ITEMS
*&---------------------------------------------------------------------*
FORM f_process_items.

  TYPES: BEGIN OF lty_done,
           matnr TYPE matnr,
           charg TYPE charg_d,
         END OF lty_done.
  DATA: ls_out  TYPE gty_out,
        lt_done TYPE SORTED TABLE OF lty_done WITH UNIQUE KEY matnr charg.

  LOOP AT gt_item INTO DATA(ls_item).
    CLEAR ls_out.
    ls_out-line  = ls_item-line.
    ls_out-matnr = ls_item-matnr.
    ls_out-charg = ls_item-charg.
    ls_out-bwtar = ls_item-bwtar.

    IF ls_item-bad = abap_true.
      ls_out-status  = gc_st_err.
      ls_out-message = ls_item-msg.
      APPEND ls_out TO gt_out.
      CONTINUE.
    ENDIF.

*   same Material + Batch (+ valuation type) twice: handled once
    READ TABLE lt_done TRANSPORTING NO FIELDS
         WITH TABLE KEY matnr = ls_item-matnr charg = ls_item-charg.
    IF sy-subrc = 0.
      ls_out-status  = gc_st_ok.
      ls_out-message = 'Duplicate line in the file - already handled'.
      APPEND ls_out TO gt_out.
      CONTINUE.
    ENDIF.
    INSERT VALUE lty_done( matnr = ls_item-matnr charg = ls_item-charg )
           INTO TABLE lt_done.

    PERFORM f_copy_batch USING ls_item CHANGING ls_out.
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_COPY_BATCH
*&      Source batch data -> new batch in the target plant, enriched
*&      with the valuation type of the file.
*&---------------------------------------------------------------------*
FORM f_copy_batch USING is_item TYPE gty_item
                  CHANGING cs_out TYPE gty_out.

  DATA: ls_att  TYPE bapibatchatt,
        lt_ret  TYPE STANDARD TABLE OF bapiret2,
        ls_ret  TYPE bapiret2,
        lv_newb TYPE charg_d,
        lv_bmat TYPE bapibatchkey-material.

  lv_bmat = is_item-matnr.

* --- batch already in the target plant ----------------------------------
  SELECT SINGLE bwtar FROM mcha INTO @DATA(lv_tbwtar)
    WHERE matnr = @is_item-matnr AND werks = @p_wdst AND charg = @is_item-charg.
  IF sy-subrc = 0.
    IF lv_tbwtar IS NOT INITIAL AND lv_tbwtar <> is_item-bwtar.
      cs_out-status  = gc_st_err.
      cs_out-message = |Batch exists in plant { p_wdst } with valuation type { lv_tbwtar }, | &&
                       |file gives { is_item-bwtar }|.
    ELSEIF lv_tbwtar IS INITIAL.
      cs_out-status  = gc_st_err.
      cs_out-message = |Batch exists in plant { p_wdst } without valuation type, | &&
                       |file gives { is_item-bwtar } - not changed|.
    ELSE.
      cs_out-status  = gc_st_ok.
      cs_out-message = |Batch already exists in plant { p_wdst } with valuation type { lv_tbwtar }|.
    ENDIF.
    RETURN.
  ENDIF.

* --- batch data at plant level in the source plant ------------------------
  CALL FUNCTION 'BAPI_BATCH_GET_DETAIL'
    EXPORTING material        = lv_bmat
              batch           = is_item-charg
              plant           = p_wsrc
    IMPORTING batchattributes = ls_att
    TABLES    return          = lt_ret.
  LOOP AT lt_ret INTO ls_ret WHERE type CA 'EA'.
    EXIT.
  ENDLOOP.
  IF sy-subrc = 0.
    cs_out-status  = gc_st_err.
    cs_out-message = |Source batch cannot be read in plant { p_wsrc }: { ls_ret-message }|.
    RETURN.
  ENDIF.

* --- enrichment with the valuation type of the file -----------------------
  ls_att-val_type = is_item-bwtar.

  IF p_test = abap_true.
    cs_out-status  = gc_st_test.
    cs_out-message = |Simulation: batch would be created in plant { p_wdst } | &&
                     |with valuation type { is_item-bwtar }|.
    RETURN.
  ENDIF.

  CLEAR lt_ret.
  CALL FUNCTION 'BAPI_BATCH_CREATE'
    EXPORTING material        = lv_bmat
              batch           = is_item-charg
              plant           = p_wdst
              batchattributes = ls_att
    IMPORTING batch           = lv_newb
    TABLES    return          = lt_ret.
  LOOP AT lt_ret INTO ls_ret WHERE type CA 'EA'.
    EXIT.
  ENDLOOP.
  IF sy-subrc = 0.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    cs_out-status  = gc_st_err.
    cs_out-message = ls_ret-message.
  ELSE.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = abap_true.
    cs_out-status  = gc_st_ok.
    cs_out-message = |Batch created in plant { p_wdst } with valuation type { is_item-bwtar }|.
  ENDIF.
ENDFORM.

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
  add_col 'STATUS'  'Status'.
  add_col 'LINE'    'File line'.
  add_col 'MATNR'   'Material'.
  add_col 'CHARG'   'Batch'.
  add_col 'BWTAR'   'Val.Type'.
  add_col 'MESSAGE' 'Message'.

  IF p_test = abap_true.
    MESSAGE 'SIMULATION - no batch created' TYPE 'S'.
  ENDIF.
  ls_lay-colwidth_optimize = abap_true.
  ls_lay-zebra = abap_true.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING is_layout   = ls_lay
              it_fieldcat = lt_fcat
    TABLES    t_outtab    = gt_out
    EXCEPTIONS program_error = 1 OTHERS = 2.
ENDFORM.
