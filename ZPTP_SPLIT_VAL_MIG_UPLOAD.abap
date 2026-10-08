*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_MIG_UPLOAD
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of the input file from the PC to the application server
*& Version : v0.1
*& Package : ZPTP_SPLIT_VAL
*&
*&---------------------------------------------------------------------*
*& Description
*&---------------------------------------------------------------------*
*& ZPTP_SPLIT_VAL_MIG can read a file located on the PC (P_LOC) only in
*& dialog: GUI_UPLOAD needs the SAP GUI, which a background job does not
*& have. This report copies the file chosen on the PC to the application
*& server, byte for byte. The migration report is then scheduled as a
*& job with "Application server" and the server path given here.
*&
*& - Run in dialog only (the local file is read through the SAP GUI).
*& - The copy is binary, so separators, decimals and line ends of the
*&   file are kept as they are.
*& - An existing server file is overwritten only after a confirmation
*&   (P_OVR = overwrite without asking).
*&
*&---------------------------------------------------------------------*
REPORT zptp_split_val_mig_upload.

DATA: gt_bin TYPE STANDARD TABLE OF x255,
      gv_len TYPE i.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  PARAMETERS: p_lfile TYPE string LOWER CASE OBLIGATORY,           " file on the PC
              p_sfile TYPE string LOWER CASE OBLIGATORY,           " target path on the server
              p_ovr   TYPE abap_bool AS CHECKBOX.                  " overwrite without asking
SELECTION-SCREEN END OF BLOCK b1.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_lfile.
  PERFORM f_f4_local.

START-OF-SELECTION.
  PERFORM f_upload.
  PERFORM f_write_server.

*&---------------------------------------------------------------------*
FORM f_f4_local.
  DATA: lt_ftab TYPE filetable,
        lv_rc   TYPE i,
        lv_usr  TYPE i.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING window_title = 'Select the input file'
    CHANGING  file_table   = lt_ftab
              rc           = lv_rc
              user_action  = lv_usr
    EXCEPTIONS OTHERS      = 1 ).
  IF sy-subrc = 0 AND lv_usr = cl_gui_frontend_services=>action_ok.
    READ TABLE lt_ftab INDEX 1 INTO DATA(ls_ftab).
    IF sy-subrc = 0.
      p_lfile = ls_ftab-filename.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_upload.
  IF sy-batch = abap_true.
    MESSAGE 'Run this report in dialog: the local file needs the SAP GUI' TYPE 'E'.
  ENDIF.
  cl_gui_frontend_services=>gui_upload(
    EXPORTING filename   = p_lfile
              filetype   = 'BIN'
    IMPORTING filelength = gv_len
    CHANGING  data_tab   = gt_bin
    EXCEPTIONS OTHERS    = 1 ).
  IF sy-subrc <> 0.
    MESSAGE |Cannot read local file { p_lfile } (rc={ sy-subrc })| TYPE 'E'.
  ENDIF.
  IF gv_len = 0.
    MESSAGE |Local file { p_lfile } is empty| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_write_server.
  DATA: lv_answer TYPE c,
        lv_left   TYPE i,
        lv_chunk  TYPE i.
  FIELD-SYMBOLS <lx_line> TYPE x255.

* existing file: ask before overwriting
  IF p_ovr = abap_false.
    OPEN DATASET p_sfile FOR INPUT IN BINARY MODE.
    IF sy-subrc = 0.
      CLOSE DATASET p_sfile.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING titlebar       = 'File exists on the server'
                  text_question  = |{ p_sfile } already exists. Overwrite?|
                  text_button_1  = 'Overwrite'
                  text_button_2  = 'Cancel'
                  default_button = '2'
        IMPORTING answer         = lv_answer.
      IF lv_answer <> '1'.
        MESSAGE 'Copy cancelled: the server file was not changed' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.

  OPEN DATASET p_sfile FOR OUTPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    MESSAGE |Cannot write { p_sfile } on the application server (path or authorization)| TYPE 'E'.
  ENDIF.

  lv_left = gv_len.
  LOOP AT gt_bin ASSIGNING <lx_line>.
    lv_chunk = nmin( val1 = lv_left val2 = 255 ).
    TRANSFER <lx_line> TO p_sfile LENGTH lv_chunk.
    lv_left = lv_left - lv_chunk.
  ENDLOOP.
  CLOSE DATASET p_sfile.

  MESSAGE |File copied: { gv_len } bytes to { p_sfile }. Schedule ZPTP_SPLIT_VAL_MIG with | &&
          |Application server and this path.| TYPE 'S'.
ENDFORM.
