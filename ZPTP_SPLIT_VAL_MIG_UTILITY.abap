*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_MIG_UTILITY
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Preparation of the Valuation Type Input File
*& Version : v0.1
*& Package : ZPTP_SPLIT_VAL
*&
*&---------------------------------------------------------------------*
*& Description
*&---------------------------------------------------------------------*
*& Generates the CSV input file of ZPTP_SPLIT_VAL_MIG from the SAP data.
*& Reads the unrestricted stock of every material in plant 1 (default
*& 8P01), looks up the material and its valuation-type segments in
*& plant 2 (default 8Q01), and downloads to the PC, through a save
*& dialog, a CSV file with the header
*&
*&     MATNR;CHARG;BWTAR;QUANTITY;UOM
*&
*&   MATNR    material number
*&   CHARG    batch, from plant 1 (blank for non-batch-managed material)
*&   BWTAR    valuation type, from plant 2
*&   QUANTITY unrestricted stock of the batch in plant 1
*&   UOM      base unit of measure
*&
*& An ALV report shows the outcome for every material / batch read,
*& including the lines left out of the file and the reason.
*&
*& Processing rules:
*&   - Stock = unrestricted stock (MCHB-CLABS), summed over the storage
*&     locations of plant 1. Non-batch-managed materials: MARD-LABST,
*&     summed over the storage locations, with a blank batch.
*&   - Material not extended to plant 2                 -> not in file.
*&   - No valuation-type segment (MBEW-BWTAR) in plant 2 -> not in file.
*&   - Several valuation types in plant 2: the first one in ascending
*&     order is taken (batches do not exist yet in plant 2).
*&   - Zero-quantity lines are left out unless P_ZERO is set.
*&   - Test mode (P_TEST, default on): only the ALV is produced, no
*&     file is built and no save dialog is opened.
*&
*&---------------------------------------------------------------------*
*& Assumptions
*&---------------------------------------------------------------------*
*& - Valuation level = plant (MBEW-BWKEY = plant 2), as in
*&   ZPTP_SPLIT_VAL_MIG.
*& - The quantity is in the material base unit.
*& - The ';' separator and the decimal point are fixed, to match the
*&   input file read by ZPTP_SPLIT_VAL_MIG.
*&
*&---------------------------------------------------------------------*
*& Related developments
*&---------------------------------------------------------------------*
*& ZPTP_SPLIT_VAL_MIG (consumes the file).
*&---------------------------------------------------------------------*
REPORT zptp_split_val_mig_utility LINE-SIZE 200.

TYPE-POOLS: abap, icon.

*&---------------------------------------------------------------------*
*&  Constants
*&---------------------------------------------------------------------*
CONSTANTS:
  gc_xchpf   TYPE marc-xchpf VALUE 'X',
  gc_sep     TYPE c          VALUE ';',
  gc_header  TYPE string     VALUE 'MATNR;CHARG;BWTAR;QUANTITY;UOM',
* status codes of the ALV
  gc_st_ok   TYPE c VALUE 'S',   " written to the file
  gc_st_zero TYPE c VALUE 'Z',   " zero quantity, left out
  gc_st_err  TYPE c VALUE 'E'.   " left out, see message

*&---------------------------------------------------------------------*
*&  Types
*&---------------------------------------------------------------------*
TYPES: BEGIN OF gty_mat,
         matnr    TYPE matnr,
         meins    TYPE meins,
         batchmgd TYPE abap_bool,
       END OF gty_mat,
       gtt_mat TYPE SORTED TABLE OF gty_mat WITH UNIQUE KEY matnr.

TYPES: BEGIN OF gty_vt,
         matnr TYPE matnr,
         bwtar TYPE bwtar_d,
       END OF gty_vt,
       gtt_vt TYPE SORTED TABLE OF gty_vt WITH UNIQUE KEY matnr bwtar.

TYPES: BEGIN OF gty_batch,
         matnr TYPE matnr,
         charg TYPE charg_d,
       END OF gty_batch,
       gtt_batch TYPE SORTED TABLE OF gty_batch WITH UNIQUE KEY matnr charg.

TYPES: BEGIN OF gty_stock,
         matnr TYPE matnr,
         charg TYPE charg_d,
         menge TYPE p LENGTH 13 DECIMALS 3,
       END OF gty_stock,
       gtt_stock TYPE STANDARD TABLE OF gty_stock WITH DEFAULT KEY.

TYPES: BEGIN OF gty_out,
         icon   TYPE icon_d,
         status TYPE c LENGTH 1,
         matnr  TYPE matnr,
         maktx  TYPE maktx,
         charg  TYPE charg_d,
         bwtar  TYPE bwtar_d,
         menge  TYPE p LENGTH 13 DECIMALS 3,
         meins  TYPE meins,
         infile TYPE abap_bool,
         newbat TYPE abap_bool,
         msg    TYPE c LENGTH 100,
       END OF gty_out,
       gtt_out TYPE STANDARD TABLE OF gty_out WITH DEFAULT KEY.

*&---------------------------------------------------------------------*
*&  Data
*&---------------------------------------------------------------------*
DATA: gt_mat1  TYPE gtt_mat,       " materials of plant 1
      gt_mat2  TYPE gtt_mat,       " materials of plant 2
      gt_vt2   TYPE gtt_vt,        " valuation-type segments of plant 2
      gt_bat2  TYPE gtt_batch,     " batches existing in plant 2
      gt_stock TYPE gtt_stock,
      gt_out   TYPE gtt_out,
      gt_file  TYPE string_table.

* reference fields for SELECT-OPTIONS
DATA: gv_sel_matnr TYPE mara-matnr,
      gv_sel_charg TYPE mchb-charg.

*&---------------------------------------------------------------------*
*&  Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_tit1.
  PARAMETERS: p_werks1 TYPE werks_d OBLIGATORY DEFAULT '8P01',   " stock plant
              p_werks2 TYPE werks_d OBLIGATORY DEFAULT '8Q01'.   " valuation-type plant
  SELECT-OPTIONS: s_matnr FOR gv_sel_matnr,
                  s_charg FOR gv_sel_charg.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_tit2.
  PARAMETERS: p_zero TYPE abap_bool AS CHECKBOX,                " include zero-quantity lines
              p_incl TYPE abap_bool AS CHECKBOX,                " ALV: only rows included in the file
              p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X'.    " test: ALV only, no file
SELECTION-SCREEN END OF BLOCK b2.

*&---------------------------------------------------------------------*
*&  Events
*&---------------------------------------------------------------------*
INITIALIZATION.
* texts set here so that no text-element maintenance is needed
  gv_tit1 = 'Selection'.
  gv_tit2 = 'Options'.
  %_p_werks1_%_app_%-text = 'Plant 1 (stock)'.
  %_p_werks2_%_app_%-text = 'Plant 2 (valuation types)'.
  %_s_matnr_%_app_%-text  = 'Material'.
  %_s_charg_%_app_%-text  = 'Batch'.
  %_p_zero_%_app_%-text   = 'Include zero-quantity lines'.
  %_p_incl_%_app_%-text   = 'Records in file only'.
  %_p_test_%_app_%-text   = 'Test mode (ALV only, no file)'.

AT SELECTION-SCREEN.
  PERFORM f_check_plants.

START-OF-SELECTION.
  PERFORM f_read_materials.
  PERFORM f_read_stock.
  PERFORM f_build_output.
  IF gt_out IS INITIAL.
    MESSAGE |No stock found in plant { p_werks1 } for the selection| TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  IF p_test = abap_false.
    PERFORM f_build_file.
    PERFORM f_download_file.
  ENDIF.
* the file is built from the full table above; the filter only
* concerns the display
  IF p_incl = abap_true.
    DELETE gt_out WHERE infile = abap_false.
    IF gt_out IS INITIAL.
      MESSAGE 'No row is included in the file' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.
  ENDIF.
  PERFORM f_display_alv.

*&---------------------------------------------------------------------*
*&      Form  F_CHECK_PLANTS
*&---------------------------------------------------------------------*
FORM f_check_plants.
  SELECT SINGLE werks FROM t001w INTO @DATA(lv_w) WHERE werks = @p_werks1.
  IF sy-subrc <> 0.
    MESSAGE |Plant { p_werks1 } does not exist| TYPE 'E'.
  ENDIF.
  SELECT SINGLE werks FROM t001w INTO @lv_w WHERE werks = @p_werks2.
  IF sy-subrc <> 0.
    MESSAGE |Plant { p_werks2 } does not exist| TYPE 'E'.
  ENDIF.
  IF p_werks1 = p_werks2.
    MESSAGE 'Plant 1 and plant 2 must be different' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_MATERIALS
*&      Plant 1: base unit and batch-management flag. Plant 2:
*&      extension of the material and its valuation-type segments.
*&---------------------------------------------------------------------*
FORM f_read_materials.
  CLEAR: gt_mat1, gt_mat2, gt_vt2.

  SELECT c~matnr, a~meins, c~xchpf, a~xchpf AS xchpf_cl
    FROM marc AS c
    INNER JOIN mara AS a ON a~matnr = c~matnr
    WHERE c~werks = @p_werks1
      AND c~matnr IN @s_matnr
    INTO TABLE @DATA(lt_marc1).

* batch-managed when the plant indicator OR the client indicator is set
  LOOP AT lt_marc1 INTO DATA(ls_marc1).
    INSERT VALUE #( matnr    = ls_marc1-matnr
                    meins    = ls_marc1-meins
                    batchmgd = xsdbool( ls_marc1-xchpf = gc_xchpf OR
                                        ls_marc1-xchpf_cl = gc_xchpf ) )
           INTO TABLE gt_mat1.
  ENDLOOP.

  SELECT matnr FROM marc
    WHERE werks = @p_werks2
      AND matnr IN @s_matnr
    INTO TABLE @DATA(lt_marc2).
  LOOP AT lt_marc2 INTO DATA(ls_marc2).
    INSERT VALUE #( matnr = ls_marc2-matnr ) INTO TABLE gt_mat2.
  ENDLOOP.

* the segment without valuation type (BWTAR blank) is not a split
* valuation segment
  SELECT matnr, bwtar FROM mbew
    WHERE bwkey = @p_werks2
      AND matnr IN @s_matnr
      AND bwtar <> @space
    INTO CORRESPONDING FIELDS OF TABLE @gt_vt2.

* batches already existing in plant 2 (to flag the missing ones in the ALV)
  CLEAR gt_bat2.
  SELECT matnr, charg FROM mcha
    WHERE werks = @p_werks2
      AND matnr IN @s_matnr
      AND charg IN @s_charg
    INTO CORRESPONDING FIELDS OF TABLE @gt_bat2.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_STOCK
*&      Unrestricted stock of plant 1, summed over storage locations.
*&---------------------------------------------------------------------*
FORM f_read_stock.
  CLEAR gt_stock.

  SELECT matnr, charg, SUM( clabs ) AS menge
    FROM mchb
    WHERE werks = @p_werks1
      AND matnr IN @s_matnr
      AND charg IN @s_charg
    GROUP BY matnr, charg
    INTO CORRESPONDING FIELDS OF TABLE @gt_stock.

* non-batch-managed materials carry a blank batch: they can only match
* a batch selection that admits a blank
  IF space IN s_charg.
    SELECT matnr, SUM( labst ) AS menge
      FROM mard
      WHERE werks = @p_werks1
        AND matnr IN @s_matnr
      GROUP BY matnr
      INTO TABLE @DATA(lt_mard).
    LOOP AT lt_mard INTO DATA(ls_mard).
      READ TABLE gt_mat1 INTO DATA(ls_mat) WITH TABLE KEY matnr = ls_mard-matnr.
      IF sy-subrc = 0 AND ls_mat-batchmgd = abap_false.
        APPEND VALUE #( matnr = ls_mard-matnr menge = ls_mard-menge ) TO gt_stock.
      ENDIF.
    ENDLOOP.
  ENDIF.

  SORT gt_stock BY matnr charg.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_BUILD_OUTPUT
*&      One output row per material / batch, with status and reason.
*&---------------------------------------------------------------------*
FORM f_build_output.
  CLEAR gt_out.

  LOOP AT gt_stock INTO DATA(ls_stk).
    DATA(ls_out) = VALUE gty_out( matnr = ls_stk-matnr
                                  charg = ls_stk-charg
                                  menge = ls_stk-menge ).
    READ TABLE gt_mat1 INTO DATA(ls_mat) WITH TABLE KEY matnr = ls_stk-matnr.
    IF sy-subrc = 0.
      ls_out-meins = ls_mat-meins.
    ENDIF.
    SELECT SINGLE maktx FROM makt INTO @ls_out-maktx
      WHERE matnr = @ls_stk-matnr AND spras = @sy-langu.

*   batch of plant 1 that does not exist yet in plant 2
    IF ls_out-charg IS NOT INITIAL.
      READ TABLE gt_bat2 TRANSPORTING NO FIELDS
           WITH TABLE KEY matnr = ls_out-matnr charg = ls_out-charg.
      IF sy-subrc <> 0.
        ls_out-newbat = abap_true.
      ENDIF.
    ENDIF.

    PERFORM f_find_bwtar USING    ls_stk-matnr
                         CHANGING ls_out-bwtar ls_out-msg.

    IF ls_out-msg IS NOT INITIAL.
      ls_out-status = gc_st_err.
    ELSEIF ls_out-menge = 0 AND p_zero = abap_false.
      ls_out-status = gc_st_zero.
      ls_out-msg    = 'Zero quantity, not included'.
    ELSE.
      ls_out-status = gc_st_ok.
      ls_out-infile = abap_true.
    ENDIF.

    ls_out-icon = SWITCH #( ls_out-status
                    WHEN gc_st_ok   THEN icon_led_green
                    WHEN gc_st_zero THEN icon_led_yellow
                    ELSE                 icon_led_red ).
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_FIND_BWTAR
*&      Valuation type of plant 2 for a material. A non-empty
*&      CV_MSG means the line cannot be written.
*&---------------------------------------------------------------------*
FORM f_find_bwtar USING    iv_matnr TYPE matnr
                  CHANGING cv_bwtar TYPE bwtar_d
                           cv_msg   TYPE gty_out-msg.
  CLEAR: cv_bwtar, cv_msg.

  READ TABLE gt_mat2 TRANSPORTING NO FIELDS WITH TABLE KEY matnr = iv_matnr.
  IF sy-subrc <> 0.
    cv_msg = |Material not extended to plant { p_werks2 }|.
    RETURN.
  ENDIF.

* GT_VT2 is sorted by material and valuation type: the first entry of
* the material is the first valuation type in ascending order. Batches
* do not exist yet in plant 2, so the batch plays no role.
  LOOP AT gt_vt2 INTO DATA(ls_vt) WHERE matnr = iv_matnr.
    cv_bwtar = ls_vt-bwtar.
    EXIT.
  ENDLOOP.
  IF sy-subrc <> 0.
    cv_msg = |No valuation type segment in plant { p_werks2 }|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_BUILD_FILE
*&---------------------------------------------------------------------*
FORM f_build_file.
  CLEAR gt_file.
  APPEND gc_header TO gt_file.

  LOOP AT gt_out INTO DATA(ls_out) WHERE infile = abap_true.
    DATA(lv_qty) = |{ ls_out-menge DECIMALS = 3 }|.
    CONDENSE lv_qty NO-GAPS.
*   unit in the logon language (internal ST -> external PC in English)
    DATA lv_uom TYPE c LENGTH 3.
    CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
      EXPORTING  input          = ls_out-meins
                 language       = sy-langu
      IMPORTING  output         = lv_uom
      EXCEPTIONS unit_not_found = 1
                 OTHERS         = 2.
    IF sy-subrc <> 0.
      lv_uom = ls_out-meins.
    ENDIF.
    APPEND |{ ls_out-matnr ALPHA = OUT }{ gc_sep }{ ls_out-charg }{ gc_sep }| &&
           |{ ls_out-bwtar }{ gc_sep }{ lv_qty }{ gc_sep }{ lv_uom }|
           TO gt_file.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DOWNLOAD_FILE
*&      Save dialog, then download to the PC.
*&---------------------------------------------------------------------*
FORM f_download_file.
  DATA: lv_filename TYPE string,
        lv_path     TYPE string,
        lv_fullpath TYPE string,
        lv_action   TYPE i.

  IF lines( gt_file ) <= 1.
    MESSAGE 'No line qualifies for the file: nothing downloaded' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA(lv_default) = |ZPTP_SPLIT_VAL_{ p_werks1 }_{ p_werks2 }_{ sy-datum }.csv|.

  cl_gui_frontend_services=>file_save_dialog(
    EXPORTING  window_title      = 'Save the Valuation Type Input File'
               default_extension = 'csv'
               default_file_name = lv_default
               file_filter       = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*|'
    CHANGING   filename          = lv_filename
               path              = lv_path
               fullpath          = lv_fullpath
               user_action       = lv_action
    EXCEPTIONS cntl_error        = 1
               error_no_gui      = 2
               not_supported_by_gui = 3
               OTHERS            = 4 ).
  IF sy-subrc <> 0.
    MESSAGE 'The save dialog could not be opened' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  IF lv_action <> cl_gui_frontend_services=>action_ok OR lv_fullpath IS INITIAL.
    MESSAGE 'Download cancelled: no file written' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  cl_gui_frontend_services=>gui_download(
    EXPORTING  filename = lv_fullpath
               filetype = 'ASC'
               codepage = '4110'          " UTF-8
    CHANGING   data_tab = gt_file
    EXCEPTIONS OTHERS   = 1 ).
  IF sy-subrc <> 0.
    MESSAGE |File { lv_fullpath } could not be written| TYPE 'S' DISPLAY LIKE 'E'.
  ELSE.
    MESSAGE |{ lines( gt_file ) - 1 } line(s) written to { lv_fullpath }| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DISPLAY_ALV
*&---------------------------------------------------------------------*
FORM f_display_alv.
  DATA lo_alv TYPE REF TO cl_salv_table.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                              CHANGING  t_table      = gt_out ).
    CATCH cx_salv_msg INTO DATA(lx_msg).
      MESSAGE lx_msg->get_text( ) TYPE 'E'.
  ENDTRY.

  lo_alv->get_functions( )->set_all( abap_true ).
  lo_alv->get_display_settings( )->set_list_header(
    COND #( WHEN p_test = abap_true
            THEN |Split valuation file (TEST, no file): { p_werks1 } -> { p_werks2 }|
            ELSE |Split valuation file: { p_werks1 } -> { p_werks2 }| ) ).
  lo_alv->get_columns( )->set_optimize( abap_true ).

  TRY.
      DATA(lo_cols) = lo_alv->get_columns( ).
      lo_cols->get_column( 'ICON'   )->set_short_text( 'St.' ).
      lo_cols->get_column( 'STATUS' )->set_visible( abap_false ).
      lo_cols->get_column( 'BWTAR'  )->set_medium_text( 'Val. type (P2)' ).
      lo_cols->get_column( 'MENGE'  )->set_medium_text( 'Quantity' ).
      lo_cols->get_column( 'INFILE' )->set_medium_text( 'In file' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'INFILE' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
      lo_cols->get_column( 'NEWBAT' )->set_medium_text( 'New batch in P2' ).
      lo_cols->get_column( 'NEWBAT' )->set_tooltip( 'Batch not yet in plant 2' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'NEWBAT' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
      lo_cols->get_column( 'MSG'    )->set_medium_text( 'Message' ).
    CATCH cx_salv_not_found.
  ENDTRY.

  lo_alv->display( ).
ENDFORM.
