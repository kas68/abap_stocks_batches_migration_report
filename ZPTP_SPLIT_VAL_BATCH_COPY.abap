*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_BATCH_COPY
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of batch master data from the source plant to the
*&           target plant, enriched with the valuation type of a file
*& Version : v0.5
*& Package : ZPTP_SPLIT_VAL
*&
*&---------------------------------------------------------------------*
*& Description
*&---------------------------------------------------------------------*
*& Reads a CSV file (separator ';', UTF-8 or Windows-1252) made of one
*& header line and several item lines:            [v0.3, was .xlsx]
*&
*&     MATERIAL;BATCH;VALUATION TYPE
*&
*&     field 1  material number
*&     field 2  batch
*&     field 3  valuation type
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
*&   - the source batch exists in the source plant (MCHA, checked before
*&     any creation); a numeric batch whose leading zeros were lost (CSV
*&     saved from Excel) is completed with zeros when that batch exists
*&     [v0.4];
*&   - a batch already existing in the target plant is not recreated:
*&     status S if its valuation type is the one of the file, E if not
*&     (a batch carries one valuation type);
*&   - the same Material + Batch twice in the file with two different
*&     valuation types: every occurrence is rejected.
*&
*& Run modes (v0.2):
*&   - Online (P_ONL, default): the file is read and checked, then the
*&     ALV lists every item. A double-click on one item asks for
*&     confirmation and creates that batch (BAPI_BATCH_CREATE + commit).
*&     The line turns green when the batch is created (or already exists
*&     with the same valuation type), red on an error. Lines rejected by
*&     the checks are red from the start. P_TEST does not apply.
*&   - Background (P_BGD): every item is processed in one run, as in v0.1;
*&     P_TEST (default on) runs all checks without creating anything. Can
*&     run as a job (SM36) with a file on the application server.
*& The file is read from the PC (dialog only) or from the application
*& server. Result: ALV list (spool in a job), no database log.
*&
*&---------------------------------------------------------------------*
*& Assumptions
*&---------------------------------------------------------------------*
*& - Line 1 is the header and is skipped. Fields after the third are
*&   ignored.
*& - When the file is prepared in Excel, the material and batch columns
*&   are formatted as text before saving as CSV (leading zeros kept).
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
  gc_st_open TYPE c VALUE ' ',      " online: ready, not processed yet [v0.2]
  gc_xchpf   TYPE xchpf VALUE 'X',
  gc_sep     TYPE c VALUE ';'.         " field separator of the CSV file [v0.3]

TYPES: BEGIN OF gty_item,
         line  TYPE i,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
         bad   TYPE abap_bool,
         msg   TYPE bapi_msg,
         note  TYPE bapi_msg,            " information, e.g. batch completed [v0.4]
       END OF gty_item,
       gtt_item TYPE STANDARD TABLE OF gty_item WITH DEFAULT KEY.

TYPES: BEGIN OF gty_out,
         status  TYPE c LENGTH 1,
         line    TYPE i,
         matnr   TYPE matnr,
         charg   TYPE charg_d,
         bwtar   TYPE bwtar_d,
         message TYPE bapi_msg,
         rowcolor TYPE c LENGTH 4,       " ALV row colour [v0.2]
         stattx   TYPE c LENGTH 20,      " status in words, ALV grouping [v0.5]
         sort_key TYPE c LENGTH 1,       " display order of the status, hidden [v0.5]
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
      gt_marc TYPE gtt_marc,
      gv_sim  TYPE abap_bool.          " simulation: background mode with P_TEST [v0.2]

*&---------------------------------------------------------------------*
*&  Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
* not OBLIGATORY: a required field left empty locks the screen at the
* first radio-button click; checked on execution in F_CHECK_SCREEN [v0.2]
  PARAMETERS: p_wsrc TYPE werks_d DEFAULT '8P01',                  " source plant
              p_wdst TYPE werks_d DEFAULT '8Q01'.                  " target plant
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_loc TYPE abap_bool RADIOBUTTON GROUP src DEFAULT 'X' USER-COMMAND src, " PC
              p_srv TYPE abap_bool RADIOBUTTON GROUP src.                              " server
  PARAMETERS: p_file TYPE string LOWER CASE.                       " checked on execution [v0.2]
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: p_onl  RADIOBUTTON GROUP run DEFAULT 'X' USER-COMMAND run, " online, item by item [v0.2]
              p_bgd  RADIOBUTTON GROUP run.                              " background, all items
  PARAMETERS: p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X' MODIF ID tst. " simulation (background)
SELECTION-SCREEN END OF BLOCK b3.

* P_TEST only applies to the background mode                  [v0.2]
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-group1 = 'TST'.
      screen-input = COND #( WHEN p_onl = abap_true THEN '0' ELSE '1' ).
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f_f4_file.

AT SELECTION-SCREEN.
  PERFORM f_check_screen.

START-OF-SELECTION.
* the online mode needs a user in front of the ALV            [v0.2]
  IF p_onl = abap_true AND sy-batch = abap_true.
    MESSAGE 'The online mode cannot run in background - choose Background' TYPE 'E'.
  ENDIF.
  gv_sim = xsdbool( p_bgd = abap_true AND p_test = abap_true ).
  PERFORM f_read_file.
  PERFORM f_read_marc.
  PERFORM f_check_items.
  IF p_onl = abap_true.
    PERFORM f_prepare_online.
  ELSE.
    PERFORM f_process_items.
  ENDIF.

END-OF-SELECTION.
  PERFORM f_display_alv.

*&---------------------------------------------------------------------*
FORM f_f4_file.
* PC: Windows file dialog (CSV and text files, or any file).
* Application server: server directory browser.               [v0.3]
  DATA: lt_ftab    TYPE filetable,
        lv_rc      TYPE i,
        lv_usr     TYPE i,
        lt_dynp    TYPE STANDARD TABLE OF dynpread,
        lv_srvpath TYPE dxfields-longpath,
        lv_srvfile TYPE dxfields-longpath.

* the radio buttons may have been changed without a screen round trip:
* read their current value from the screen
  lt_dynp = VALUE #( ( fieldname = 'P_LOC' ) ( fieldname = 'P_SRV' ) ).
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING  dyname     = sy-repid
               dynumb     = sy-dynnr
    TABLES     dynpfields = lt_dynp
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc = 0.
    READ TABLE lt_dynp INTO DATA(ls_dynp) WITH KEY fieldname = 'P_SRV'.
    IF sy-subrc = 0.
      p_srv = ls_dynp-fieldvalue.
      p_loc = xsdbool( p_srv <> abap_true ).
    ENDIF.
  ENDIF.

  IF p_srv = abap_true.
*   P_FILE is a string: pass a DXFIELDS-LONGPATH copy (typed parameter)
    lv_srvpath = p_file.
    CALL FUNCTION 'F4_DXFILENAME_TOPRECURSION'
      EXPORTING  i_location_flag = 'A'              " application server
                 i_server        = ' '
                 i_path          = lv_srvpath
                 filemask        = '*.*'
                 fileoperation   = 'R'
      IMPORTING  o_path          = lv_srvfile
      EXCEPTIONS rfc_error       = 1
                 error_with_gui  = 2
                 OTHERS          = 3.
    IF sy-subrc = 0 AND lv_srvfile IS NOT INITIAL.
      p_file = lv_srvfile.
    ENDIF.
    RETURN.
  ENDIF.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING  window_title            = 'Select the CSV file'
*              no filter: every file of the folder is listed, whatever
*              its extension (.csv, .txt, .CSV ...)                   [v0.3]
               multiselection          = abap_false
    CHANGING   file_table              = lt_ftab
               rc                      = lv_rc
               user_action             = lv_usr
    EXCEPTIONS file_open_dialog_failed = 1
               cntl_error              = 2
               error_no_gui            = 3
               not_supported_by_gui    = 4
               OTHERS                  = 5 ).
  IF sy-subrc <> 0.
    MESSAGE |The file dialog could not be opened (return code { sy-subrc })| TYPE 'S'
            DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF lv_usr = cl_gui_frontend_services=>action_ok.
    READ TABLE lt_ftab INDEX 1 INTO DATA(ls_ftab).
    IF sy-subrc = 0.
      p_file = ls_ftab-filename.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_check_screen.
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
* a job has no SAP GUI: no PC file, no online mode            [v0.2]
  IF sy-ucomm = 'SJOB' AND p_loc = abap_true.
    MESSAGE 'A background job cannot read a PC file - choose Application server' TYPE 'E'.
  ENDIF.
  IF sy-ucomm = 'SJOB' AND p_onl = abap_true.
    MESSAGE 'A background job needs the Background run mode' TYPE 'E'.
  ENDIF.
  IF p_wsrc IS INITIAL OR p_wdst IS INITIAL.
    MESSAGE 'Source and target plant are required' TYPE 'E'.
  ENDIF.
  IF p_file IS INITIAL.
    MESSAGE 'Please specify the CSV file path' TYPE 'E'.
  ENDIF.
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
*&      Form  F_READ_FILE   (CSV from PC or application server)
*&---------------------------------------------------------------------*
FORM f_read_file.

  DATA: lt_bin   TYPE STANDARD TABLE OF x255,
        lv_len   TYPE i,
        lv_xstr  TYPE xstring,
        lv_chunk TYPE x255,
        lv_text  TYPE string,
        lt_lines TYPE string_table,
        lv_line  TYPE string,
        lt_field TYPE string_table,
        ls_item  TYPE gty_item,
        lv_matnr TYPE string,
        lv_charg TYPE string,
        lv_bwtar TYPE string,
        lv_row   TYPE i.

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

* --- decode: UTF-8 first, then Windows-1252 (older Excel "CSV")  [v0.3]
  TRY.
      cl_abap_conv_in_ce=>create( encoding    = 'UTF-8'
                                  ignore_cerr = abap_false
                                  input       = lv_xstr )->read( IMPORTING data = lv_text ).
    CATCH cx_root.
      TRY.
          cl_abap_conv_in_ce=>create( encoding    = '1160'
                                      ignore_cerr = abap_true
                                      input       = lv_xstr )->read( IMPORTING data = lv_text ).
        CATCH cx_root.
          MESSAGE |Cannot decode file { p_file }| TYPE 'E'.
      ENDTRY.
  ENDTRY.
  IF lv_text IS NOT INITIAL AND lv_text(1) = cl_abap_conv_in_ce=>uccp( 'FEFF' ).
    lv_text = lv_text+1.                                " byte order mark
  ENDIF.
  REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
          IN lv_text WITH cl_abap_char_utilities=>newline.
  SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

* --- items: line 1 = header; MATERIAL;BATCH;VALUATION TYPE ----------
  LOOP AT lt_lines INTO lv_line.
    lv_row = sy-tabix.
    IF lv_row = 1.
      CONTINUE.
    ENDIF.
    CLEAR: ls_item, lv_matnr, lv_charg, lv_bwtar, lt_field.
    SPLIT lv_line AT gc_sep INTO TABLE lt_field.
    READ TABLE lt_field INDEX 1 INTO lv_matnr.
    READ TABLE lt_field INDEX 2 INTO lv_charg.
    READ TABLE lt_field INDEX 3 INTO lv_bwtar.
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

* --- source batch exists in the source plant (MCHA)              [v0.4]
* runs first: a batch completed with leading zeros changes the key used
* by the next checks
  PERFORM f_check_source_batch.

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
*&      Form  F_CHECK_SOURCE_BATCH                              [v0.4]
*&      The batch of the file must exist in the source plant, otherwise
*&      BAPI_BATCH_GET_DETAIL fails at creation. A numeric batch without
*&      its leading zeros (lost when the CSV is saved from Excel) is
*&      completed to 10 characters when that batch exists.
*&---------------------------------------------------------------------*
FORM f_check_source_batch.
  DATA: lv_full TYPE charg_d,
        lv_x    TYPE charg_d.

  LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<ls_item>)
       WHERE bad = abap_false AND matnr IS NOT INITIAL AND charg IS NOT INITIAL.

    SELECT SINGLE charg FROM mcha INTO @lv_x
      WHERE matnr = @<ls_item>-matnr
        AND werks = @p_wsrc
        AND charg = @<ls_item>-charg.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.

*   numeric batch shorter than 10 characters: try with leading zeros
    CLEAR lv_full.
    IF <ls_item>-charg CO '0123456789 ' AND strlen( <ls_item>-charg ) < 10.
      lv_full = <ls_item>-charg.
      SHIFT lv_full RIGHT DELETING TRAILING space.
      OVERLAY lv_full WITH '0000000000'.
      SELECT SINGLE charg FROM mcha INTO @lv_x
        WHERE matnr = @<ls_item>-matnr
          AND werks = @p_wsrc
          AND charg = @lv_full.
      IF sy-subrc = 0.
        <ls_item>-note  = |batch { <ls_item>-charg } of the file completed to { lv_full }|.
        <ls_item>-charg = lv_full.
        CONTINUE.
      ENDIF.
    ENDIF.

    <ls_item>-bad = abap_true.
    <ls_item>-msg = |Batch { <ls_item>-charg } of material { <ls_item>-matnr ALPHA = OUT } | &&
                    |does not exist in plant { p_wsrc }| &&
                    |{ COND string( WHEN lv_full IS NOT INITIAL
                                    THEN | (nor { lv_full })| ) }| &&
                    | - check the batch number in the file (leading zeros?)|.
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
    IF ls_item-note IS NOT INITIAL.
      ls_out-message = |{ ls_out-message } ({ ls_item-note })|.
    ENDIF.
    PERFORM f_set_color CHANGING ls_out.
    APPEND ls_out TO gt_out.
  ENDLOOP.

  LOOP AT gt_out ASSIGNING FIELD-SYMBOL(<ls_col>) WHERE rowcolor IS INITIAL.
    PERFORM f_set_color CHANGING <ls_col>.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PREPARE_ONLINE                                  [v0.2]
*&      Online mode: one ALV row per item, nothing created yet. Items
*&      rejected by the checks are red; the others wait for a double-click.
*&---------------------------------------------------------------------*
FORM f_prepare_online.
  DATA ls_out TYPE gty_out.

  LOOP AT gt_item INTO DATA(ls_item).
    CLEAR ls_out.
    ls_out-line  = ls_item-line.
    ls_out-matnr = ls_item-matnr.
    ls_out-charg = ls_item-charg.
    ls_out-bwtar = ls_item-bwtar.
    IF ls_item-bad = abap_true.
      ls_out-status  = gc_st_err.
      ls_out-message = ls_item-msg.
    ELSE.
      ls_out-status  = gc_st_open.
      ls_out-message = |Ready - double-click to create the batch in plant { p_wdst }|.
      IF ls_item-note IS NOT INITIAL.
        ls_out-message = |{ ls_out-message } ({ ls_item-note })|.
      ENDIF.
    ENDIF.
    PERFORM f_set_color CHANGING ls_out.
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_USER_COMMAND                                    [v0.2]
*&      ALV callback, online mode. Double-click (&IC1) on one item:
*&      confirmation, batch creation and commit, then the row is
*&      refreshed in place - green on success, red on error.
*&---------------------------------------------------------------------*
FORM f_user_command USING r_ucomm     TYPE sy-ucomm
                          rs_selfield TYPE slis_selfield.
  DATA: ls_item   TYPE gty_item,
        lv_answer TYPE c,
        lv_disp   TYPE c.

  CHECK p_onl = abap_true AND r_ucomm = '&IC1'.

  READ TABLE gt_out ASSIGNING FIELD-SYMBOL(<ls_out>) INDEX rs_selfield-tabindex.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  CASE <ls_out>-status.
    WHEN gc_st_ok.
      MESSAGE |Batch { <ls_out>-charg } is already in plant { p_wdst }| TYPE 'S'.
      RETURN.
    WHEN gc_st_err.
*     a line rejected by the file checks cannot be created; a line that
*     failed at creation can be tried again
      READ TABLE gt_item INTO ls_item WITH KEY line = <ls_out>-line.
      IF sy-subrc = 0 AND ls_item-bad = abap_true.
        MESSAGE |Line { <ls_out>-line } cannot be created: { ls_item-msg }| TYPE 'S'
                DISPLAY LIKE 'E'.
        RETURN.
      ENDIF.
  ENDCASE.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar       = 'Create batch'
      text_question  = |Create batch { <ls_out>-charg } of material { <ls_out>-matnr ALPHA = OUT } | &&
                       |in plant { p_wdst } with valuation type { <ls_out>-bwtar }?|
      text_button_1  = 'Create'
      text_button_2  = 'Cancel'
      default_button = '1'
    IMPORTING
      answer         = lv_answer.
  IF lv_answer <> '1'.
    RETURN.
  ENDIF.

  READ TABLE gt_item INTO ls_item WITH KEY line = <ls_out>-line.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  PERFORM f_copy_batch USING ls_item CHANGING <ls_out>.
  IF ls_item-note IS NOT INITIAL.
    <ls_out>-message = |{ <ls_out>-message } ({ ls_item-note })|.
  ENDIF.
  PERFORM f_set_color CHANGING <ls_out>.

  lv_disp = COND #( WHEN <ls_out>-status = gc_st_err THEN 'E' ELSE 'S' ).
  MESSAGE <ls_out>-message TYPE 'S' DISPLAY LIKE lv_disp.
  rs_selfield-refresh    = abap_true.
  rs_selfield-row_stable = abap_true.
  rs_selfield-col_stable = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_SET_COLOR                                       [v0.2]
*&      Row colour: green = created or already there, red = error,
*&      yellow = simulated, none = waiting (online).
*&---------------------------------------------------------------------*
FORM f_set_color CHANGING cs_out TYPE gty_out.
  cs_out-rowcolor = SWITCH #( cs_out-status
                              WHEN gc_st_ok   THEN 'C510'
                              WHEN gc_st_err  THEN 'C610'
                              WHEN gc_st_test THEN 'C310'
                              ELSE space ).
* grouping of the ALV: ready first (online), then simulated, created,
* errors                                                       [v0.5]
  cs_out-stattx   = SWITCH #( cs_out-status
                              WHEN gc_st_ok   THEN 'Created / exists'
                              WHEN gc_st_err  THEN 'Error'
                              WHEN gc_st_test THEN 'Simulated'
                              ELSE 'Ready' ).
  cs_out-sort_key = SWITCH #( cs_out-status
                              WHEN gc_st_test THEN '2'
                              WHEN gc_st_ok   THEN '3'
                              WHEN gc_st_err  THEN '4'
                              ELSE '1' ).
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

  IF gv_sim = abap_true.
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
        lt_sort TYPE slis_t_sortinfo_alv,
        ls_lay  TYPE slis_layout_alv.

  DEFINE add_col.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1. ls_fcat-seltext_l = &2.
    ls_fcat-seltext_m = &2. ls_fcat-seltext_s = &2.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.
  add_col 'STATTX'  'Status'.
  add_col 'STATUS'  'St'.
  add_col 'LINE'    'File line'.
  add_col 'MATNR'   'Material'.
  add_col 'CHARG'   'Batch'.
  add_col 'BWTAR'   'Val.Type'.
  add_col 'MESSAGE' 'Message'.
* technical sort key, not displayed                            [v0.5]
  add_col 'SORT_KEY' 'Sort'.
  ls_fcat-no_out = abap_true.
  MODIFY lt_fcat FROM ls_fcat INDEX lines( lt_fcat ).
  lt_sort = VALUE #( ( spos = 1 fieldname = 'SORT_KEY' up = abap_true )
                     ( spos = 2 fieldname = 'STATTX'   up = abap_true group = 'UL' )
                     ( spos = 3 fieldname = 'LINE'     up = abap_true ) ).

  IF gv_sim = abap_true.
    MESSAGE 'SIMULATION - no batch created' TYPE 'S'.
  ENDIF.
  ls_lay-colwidth_optimize = abap_true.
  ls_lay-info_fieldname    = 'ROWCOLOR'.                       " [v0.2]
  DATA(lv_title) = CONV lvc_title( COND #( WHEN p_onl = abap_true
                     THEN |Double-click an item to create its batch in plant { p_wdst }|
                     WHEN gv_sim = abap_true
                     THEN |Simulation - batches { p_wsrc } -> { p_wdst }|
                     ELSE |Batches created { p_wsrc } -> { p_wdst }| ) ).
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING i_callback_program      = sy-repid
              i_callback_user_command = 'F_USER_COMMAND'
              i_grid_title            = lv_title
              is_layout               = ls_lay
              it_fieldcat             = lt_fcat
              it_sort                 = lt_sort
    TABLES    t_outtab                = gt_out
    EXCEPTIONS program_error = 1 OTHERS = 2.
ENDFORM.
