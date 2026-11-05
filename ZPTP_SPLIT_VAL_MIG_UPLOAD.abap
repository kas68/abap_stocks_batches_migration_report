*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_MIG_UPLOAD
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of the input file from the PC to the application server
*& Version : v0.4
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
*& - Target on the server (v0.2), two ways:
*&     P_TFULL  full path typed by the user (as in v0.1);
*&     P_TAL11  directory name as shown in transaction AL11.
*&              The directory is either an SAP profile parameter
*&              (DIR_HOME, DIR_TEMP, ...) or a user-defined AL11
*&              directory (table USER_DIR). F4 lists both with their
*&              path.
*&   The file always keeps the name it has on the PC (v0.4): only the
*&   target directory is chosen.
*&   Full path: F4 lists the files of the directory typed in the field
*&   (DIR_HOME when none), as in ZPTP_SPLIT_VAL_BATCH_COPY; a path ending
*&   with / or \ is a directory and receives the name of the PC file.
*&   [v0.3]
*&   The full path actually written is shown at the end, to be entered
*&   in ZPTP_SPLIT_VAL_MIG / ZPTP_SPLIT_VAL_BATCH_COPY.
*&
*&---------------------------------------------------------------------*
*& To verify in the sandbox (v0.2): field names of USER_DIR (ALIASS =
*& directory name shown in AL11, DIRNAME = path), as in SE11.
*&---------------------------------------------------------------------*
REPORT zptp_split_val_mig_upload.

DATA: gt_bin    TYPE STANDARD TABLE OF x255,
      gv_len    TYPE i,
      gv_target TYPE string.             " full server path written [v0.2]

* directory of AL11, for the F4 list. Typed on the dictionary: the
* value-help function reads the field descriptions from it.   [v0.2]
TYPES: BEGIN OF gty_dir,
         aliass  TYPE user_dir-aliass,     " directory name as in AL11
         dirname TYPE user_dir-dirname,    " path
       END OF gty_dir,
       gtt_dir TYPE STANDARD TABLE OF gty_dir WITH DEFAULT KEY.

* Fields are not OBLIGATORY: a required field left empty locks the
* screen at the first radio-button click. Checked on execution.
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  PARAMETERS: p_lfile TYPE string LOWER CASE.                      " file on the PC
  SELECTION-SCREEN SKIP.
  PARAMETERS: p_tfull RADIOBUTTON GROUP tgt DEFAULT 'X' USER-COMMAND tgt, " full server path
              p_tal11 RADIOBUTTON GROUP tgt.                       " AL11 directory + file name
* the file keeps the name it has on the PC: only the directory is
* chosen                                                       [v0.4]
  PARAMETERS: p_sfile TYPE string LOWER CASE MODIF ID ful,         " target directory on the server
              p_aldir TYPE user_dir-aliass MODIF ID al1.               " directory name (AL11)
  SELECTION-SCREEN SKIP.
  PARAMETERS: p_ovr   TYPE abap_bool AS CHECKBOX.                  " overwrite without asking
SELECTION-SCREEN END OF BLOCK b1.

* only the fields of the chosen target are ready for input     [v0.2]
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'FUL'.
        screen-input = COND #( WHEN p_tfull = abap_true THEN '1' ELSE '0' ).
        MODIFY SCREEN.
      WHEN 'AL1'.
        screen-input = COND #( WHEN p_tal11 = abap_true THEN '1' ELSE '0' ).
        MODIFY SCREEN.
    ENDCASE.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_lfile.
  PERFORM f_f4_local.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_sfile.
  PERFORM f_f4_server.                                          " [v0.3]

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_aldir.
  PERFORM f_f4_al11.

AT SELECTION-SCREEN.
  PERFORM f_check_screen.

START-OF-SELECTION.
  PERFORM f_resolve_target.
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
*&      Form  F_CHECK_SCREEN                                    [v0.2]
*&      Mandatory fields, on execution only.
*&---------------------------------------------------------------------*
FORM f_check_screen.
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'PRIN' OR sy-ucomm = 'SJOB'.
  IF p_lfile IS INITIAL.
    MESSAGE 'Please select the file on the PC' TYPE 'E'.
  ENDIF.
  IF p_tfull = abap_true AND p_sfile IS INITIAL.
    MESSAGE 'Please enter the target directory on the server' TYPE 'E'.
  ENDIF.
  IF p_tal11 = abap_true AND p_aldir IS INITIAL.
    MESSAGE 'Please enter the AL11 directory name (F4 lists them)' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DIR_PATH                                        [v0.2]
*&      Path of a directory name of AL11: profile parameter DIR_* or
*&      user-defined directory (USER_DIR). Blank when unknown.
*&---------------------------------------------------------------------*
FORM f_dir_path USING    iv_dirname TYPE csequence
                CHANGING cv_path    TYPE csequence.
  DATA: lv_name  TYPE spfl_parameter_name,
        lv_value TYPE spfl_parameter_value,
        lv_dir   TYPE string.

  CLEAR cv_path.
  lv_dir = to_upper( condense( val = iv_dirname ) ).
  IF lv_dir IS INITIAL.
    RETURN.
  ENDIF.

* SAP directories of AL11 are profile parameters (DIR_HOME, ...)
  IF lv_dir CP 'DIR_*'.
    lv_name = lv_dir.
    cl_spfl_profile_parameter=>get_value( EXPORTING name  = lv_name
                                          IMPORTING value = lv_value ).
    cv_path = lv_value.
    IF cv_path IS NOT INITIAL.
      RETURN.
    ENDIF.
  ENDIF.

* user-defined directories of AL11
  SELECT SINGLE dirname FROM user_dir INTO @DATA(lv_udir)
    WHERE aliass = @lv_dir.
  IF sy-subrc = 0.
    cv_path = lv_udir.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_AL11                                         [v0.2]
*&      Value list of the AL11 directories with their path.
*&---------------------------------------------------------------------*
FORM f_f4_al11.
  DATA: lt_dir  TYPE gtt_dir,
        ls_dir  TYPE gty_dir,
        lt_ret  TYPE STANDARD TABLE OF ddshretval,
        lv_path TYPE string.

* SAP directories commonly used for file exchange
  DATA(lt_std) = VALUE string_table( ( `DIR_HOME` ) ( `DIR_TEMP` ) ( `DIR_TRANS` )
                                     ( `DIR_SAPUSERS` ) ( `DIR_GLOBAL` ) ( `DIR_DATA` ) ).
  LOOP AT lt_std INTO DATA(lv_std).
    PERFORM f_dir_path USING lv_std CHANGING lv_path.
    IF lv_path IS NOT INITIAL.
      ls_dir-aliass  = lv_std.
      ls_dir-dirname = lv_path.
      APPEND ls_dir TO lt_dir.
    ENDIF.
  ENDLOOP.

* user-defined directories
  SELECT aliass, dirname FROM user_dir INTO TABLE @DATA(lt_user).
  SORT lt_user BY aliass.
  DELETE ADJACENT DUPLICATES FROM lt_user COMPARING aliass.
  LOOP AT lt_user INTO DATA(ls_user).
    ls_dir-aliass  = ls_user-aliass.
    ls_dir-dirname = ls_user-dirname.
    APPEND ls_dir TO lt_dir.
  ENDLOOP.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'ALIASS'
               dynpprog        = sy-repid
               dynpnr          = sy-dynnr
               dynprofield     = 'P_ALDIR'
               window_title    = 'Directories (AL11)'
               value_org       = 'S'
    TABLES     value_tab       = lt_dir
               return_tab      = lt_ret
    EXCEPTIONS parameter_error = 1
               no_values_found = 2
               OTHERS          = 3.
  IF sy-subrc <> 0.
    MESSAGE 'No AL11 directory could be listed - type the full path instead' TYPE 'S'
            DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_RESOLVE_TARGET                                  [v0.2]
*&      Full server path from the chosen target option.
*&---------------------------------------------------------------------*
FORM f_resolve_target.
* The file keeps the name it has on the PC; only the directory comes
* from the screen.                                             [v0.4]
  DATA: lv_path TYPE string,
        lv_file TYPE string,
        lv_last TYPE string,
        lv_sep  TYPE c.

* name of the PC file, without its folder
  lv_file = p_lfile.
  FIND ALL OCCURRENCES OF REGEX '[\\/]' IN lv_file MATCH OFFSET DATA(lv_poff).
  IF sy-subrc = 0.
    lv_file = substring( val = lv_file off = lv_poff + 1 ).
  ENDIF.

  IF p_tfull = abap_true.
    lv_path = condense( p_sfile ).
*   a path ending with a file name (last part with a dot, e.g. picked
*   with F4): keep its directory only
    FIND ALL OCCURRENCES OF REGEX '[\\/]' IN lv_path MATCH OFFSET DATA(lv_doff).
    IF sy-subrc = 0.
      lv_last = substring( val = lv_path off = lv_doff + 1 ).
      IF lv_last CA '.'.
        lv_path = substring( val = lv_path len = lv_doff + 1 ).
      ENDIF.
    ENDIF.
  ELSE.
    PERFORM f_dir_path USING p_aldir CHANGING lv_path.
    IF lv_path IS INITIAL.
      MESSAGE |Directory { p_aldir } is not known in AL11| TYPE 'E'.
    ENDIF.
  ENDIF.

* separator of the server: '\' on Windows paths, '/' otherwise
  lv_sep = COND #( WHEN lv_path CA '\' THEN '\' ELSE '/' ).
  IF substring( val = lv_path off = strlen( lv_path ) - 1 len = 1 ) <> lv_sep.
    lv_path = lv_path && lv_sep.
  ENDIF.
  gv_target = lv_path && lv_file.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_SERVER                                       [v0.3]
*&      Same file list as ZPTP_SPLIT_VAL_BATCH_COPY: files of the
*&      directory typed in P_SFILE, or DIR_HOME when none. To go up or
*&      elsewhere, type that directory in the field and press F4 again.
*&      Choosing a file keeps its directory only: the file written on
*&      the server always has the name of the PC file (v0.4).
*&---------------------------------------------------------------------*
FORM f_f4_server.
  DATA: lt_dynp  TYPE STANDARD TABLE OF dynpread,
        lv_path  TYPE string,
        lv_dir   TYPE eps2filnam,
        lv_sep   TYPE c,
        lv_value TYPE spfl_parameter_value,
        lt_list  TYPE STANDARD TABLE OF eps2fili,
        lt_ret   TYPE STANDARD TABLE OF ddshretval.

* path typed but not yet transferred to the program
  lt_dynp = VALUE #( ( fieldname = 'P_SFILE' ) ).
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING  dyname     = sy-repid
               dynumb     = sy-dynnr
    TABLES     dynpfields = lt_dynp
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc = 0.
    READ TABLE lt_dynp INTO DATA(ls_dynp) INDEX 1.
    IF sy-subrc = 0.
      p_sfile = condense( CONV string( ls_dynp-fieldvalue ) ).
    ENDIF.
  ENDIF.

  lv_path = p_sfile.
  IF lv_path CA '/\'.
*   directory = everything before the last separator
    FIND ALL OCCURRENCES OF REGEX '[\\/]' IN lv_path MATCH OFFSET DATA(lv_off).
    lv_sep = lv_path+lv_off(1).
    IF lv_off = 0.
      lv_dir = lv_sep.                                  " root directory
    ELSE.
      lv_dir = substring( val = lv_path len = lv_off ).
    ENDIF.
  ELSE.
    cl_spfl_profile_parameter=>get_value( EXPORTING name  = 'DIR_HOME'
                                          IMPORTING value = lv_value ).
    lv_dir = lv_value.
    lv_sep = COND #( WHEN lv_dir CA '\' THEN '\' ELSE '/' ).
  ENDIF.
  IF lv_dir IS INITIAL.
    MESSAGE 'Type a directory in the file field, then press F4' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
    EXPORTING  iv_dir_name            = lv_dir
    TABLES     dir_list               = lt_list
    EXCEPTIONS invalid_eps_subdir     = 1
               sapgparam_failed       = 2
               build_directory_failed = 3
               no_authorization       = 4
               read_directory_failed  = 5
               too_many_read_errors   = 6
               empty_directory_list   = 7
               OTHERS                 = 8.
  CASE sy-subrc.
    WHEN 0.
    WHEN 4.
      MESSAGE |No authorization to read directory { lv_dir } (S_DATASET)| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    WHEN 7.
      MESSAGE |Directory { lv_dir } is empty| TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    WHEN OTHERS.
      MESSAGE |Directory { lv_dir } cannot be read (return code { sy-subrc }) - check the path in AL11|
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDCASE.

  SORT lt_list BY name.
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'NAME'
               window_title    = CONV char40( |Files in { lv_dir }| )
               value_org       = 'S'
    TABLES     value_tab       = lt_list
               return_tab      = lt_ret
    EXCEPTIONS parameter_error = 1
               no_values_found = 2
               OTHERS          = 3.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  READ TABLE lt_ret INTO DATA(ls_ret) INDEX 1.
  IF sy-subrc = 0 AND ls_ret-fieldval IS NOT INITIAL.
*   the file keeps its PC name: only the directory is kept    [v0.4]
    p_sfile = COND #( WHEN substring( val = CONV string( lv_dir ) off = strlen( lv_dir ) - 1 len = 1 ) = lv_sep
                      THEN |{ lv_dir }|
                      ELSE |{ lv_dir }{ lv_sep }| ).
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
    OPEN DATASET gv_target FOR INPUT IN BINARY MODE.
    IF sy-subrc = 0.
      CLOSE DATASET gv_target.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING titlebar       = 'File exists on the server'
                  text_question  = |{ gv_target } already exists. Overwrite?|
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

  OPEN DATASET gv_target FOR OUTPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    MESSAGE |Cannot write { gv_target } on the application server (path or authorization)| TYPE 'E'.
  ENDIF.

  lv_left = gv_len.
  LOOP AT gt_bin ASSIGNING <lx_line>.
    lv_chunk = nmin( val1 = lv_left val2 = 255 ).
    TRANSFER <lx_line> TO gv_target LENGTH lv_chunk.
    lv_left = lv_left - lv_chunk.
  ENDLOOP.
  CLOSE DATASET gv_target.

* the full path is what the reading programs need               [v0.2]
  MESSAGE |File copied: { gv_len } bytes to { gv_target } - enter this path with | &&
          |"Application server" in the migration or batch copy program| TYPE 'S'.
ENDFORM.
