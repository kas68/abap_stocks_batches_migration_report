*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_MIG_UPLOAD
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of a file between the PC and the application server
*& Version : v0.6
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
*& Download (v0.5) - block "Direction": P_UPL upload PC -> server (as
*& before, default) or P_DNL download server -> PC:
*&   - P_DFILE: full path of the file on the server. F4 lists the files
*&     of the directory typed in the field: a path, an AL11 directory
*&     name (DIR_HOME, DIR_TEMP, user-defined), or DIR_HOME when empty.
*&   - P_DDIR: folder on the PC (F4: folder dialog). The file keeps the
*&     name it has on the server.
*&   - P_DOVR: replace a file of the same name on the PC without asking.
*&   The copy is binary (READ DATASET ... IN BINARY MODE, then
*&   GUI_DOWNLOAD as BIN), so the content is unchanged. Dialog only.
*&   Needs S_DATASET read access to the server file.
*&
*& Application server (v0.6) - block "Application server": P_ASRV is the
*& instance (as in SM51) whose file system is read or written, default
*& the current one (profile parameter rdisp/myname). F4 lists the active
*& instances (TH_SERVER_LIST). Every server file access - directory
*& paths of AL11, directory lists, existence check, read, write - goes
*& through the remote-enabled modules of function group ZPTP_SVAL_FILE,
*& called with DESTINATION <instance> when another server is chosen
*& (an instance name of the same system is a valid RFC destination),
*& locally otherwise. Needs S_RFC for ZPTP_SVAL_FILE. Use it when the
*& directory is local to each server: the file must be on the server
*& where the program that reads it (job of ZPTP_SPLIT_VAL_MIG) runs.
*&
*&---------------------------------------------------------------------*
*& To verify in the sandbox (v0.2): field names of USER_DIR (ALIASS =
*& directory name shown in AL11, DIRNAME = path), as in SE11.
*&---------------------------------------------------------------------*
REPORT zptp_split_val_mig_upload.

DATA: gt_bin    TYPE solix_tab,          " file content, both directions (SOLIX for RFC) [v0.6]
      gv_len    TYPE i,
      gv_own    TYPE msxxlist-name,      " instance of the current session [v0.6]
      gv_dest   TYPE msxxlist-name,      " RFC destination = instance, blank = current server [v0.6]
      gv_target TYPE string.             " full server path written [v0.2]

* directory of AL11, for the F4 list. Typed on the dictionary: the
* value-help function reads the field descriptions from it.   [v0.2]
TYPES: BEGIN OF gty_dir,
         aliass  TYPE user_dir-aliass,     " directory name as in AL11
         dirname TYPE user_dir-dirname,    " path
       END OF gty_dir,
       gtt_dir TYPE STANDARD TABLE OF gty_dir WITH DEFAULT KEY.
* directory list of a server                                   [v0.6]
TYPES: gtt_fili TYPE STANDARD TABLE OF eps2fili WITH DEFAULT KEY.

* direction of the copy                                          [v0.5]
SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME TITLE TEXT-b00.
  PARAMETERS: p_upl RADIOBUTTON GROUP dir DEFAULT 'X' USER-COMMAND dir, " upload PC -> server
              p_dnl RADIOBUTTON GROUP dir.                         " download server -> PC
SELECTION-SCREEN END OF BLOCK b0.

* application server whose file system is used                  [v0.6]
SELECTION-SCREEN BEGIN OF BLOCK b9 WITH FRAME TITLE TEXT-b09.
  PARAMETERS: p_asrv TYPE msxxlist-name LOWER CASE.               " instance, as in SM51
SELECTION-SCREEN END OF BLOCK b9.

* default: the server of the current session                    [v0.6]
INITIALIZATION.
  PERFORM f_own_server.
  p_asrv = gv_own.

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

* download: server file -> PC folder                             [v0.5]
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  PARAMETERS: p_dfile TYPE string LOWER CASE.                      " file on the server (full path)
  PARAMETERS: p_ddir  TYPE string LOWER CASE.                      " folder on the PC
  PARAMETERS: p_dovr  TYPE abap_bool AS CHECKBOX.                  " replace on the PC without asking
SELECTION-SCREEN END OF BLOCK b2.

* only the fields of the chosen target are ready for input     [v0.2]
* and only those of the chosen direction                        [v0.5]
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'FUL'.
        screen-input = COND #( WHEN p_tfull = abap_true AND p_upl = abap_true THEN '1' ELSE '0' ).
        MODIFY SCREEN.
      WHEN 'AL1'.
        screen-input = COND #( WHEN p_tal11 = abap_true AND p_upl = abap_true THEN '1' ELSE '0' ).
        MODIFY SCREEN.
    ENDCASE.
    IF screen-name = 'P_LFILE' OR screen-name = 'P_TFULL' OR screen-name = 'P_TAL11'
       OR screen-name = 'P_OVR'.
      screen-input = COND #( WHEN p_upl = abap_true THEN '1' ELSE '0' ).
      MODIFY SCREEN.
    ELSEIF screen-name = 'P_DFILE' OR screen-name = 'P_DDIR' OR screen-name = 'P_DOVR'.
      screen-input = COND #( WHEN p_dnl = abap_true THEN '1' ELSE '0' ).
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_asrv.
  PERFORM f_f4_asrv.                                            " [v0.6]

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_lfile.
  PERFORM f_f4_local.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_sfile.
  PERFORM f_f4_server.                                          " [v0.3]

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_aldir.
  PERFORM f_f4_al11.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_dfile.
  PERFORM f_f4_server_file.                                     " [v0.5]

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_ddir.
  PERFORM f_f4_pc_folder.                                       " [v0.5]

AT SELECTION-SCREEN.
  PERFORM f_check_screen.

START-OF-SELECTION.
  PERFORM f_set_dest.                                           " [v0.6]
  IF p_dnl = abap_true.                                         " [v0.5]
    PERFORM f_read_server.
    PERFORM f_download.
  ELSE.
    PERFORM f_resolve_target.
    PERFORM f_upload.
    PERFORM f_write_server.
  ENDIF.

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
* application server: an active instance of the system         [v0.6]
  IF p_asrv IS INITIAL.
    MESSAGE 'Please enter the application server (F4 lists them)' TYPE 'E'.
  ENDIF.
  PERFORM f_check_asrv.
* download                                                       [v0.5]
  IF p_dnl = abap_true.
    IF p_dfile IS INITIAL.
      MESSAGE 'Please enter the file on the server (F4 lists the files of a directory)' TYPE 'E'.
    ENDIF.
    IF p_ddir IS INITIAL.
      MESSAGE 'Please select the folder on the PC' TYPE 'E'.
    ENDIF.
    RETURN.
  ENDIF.
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
* resolved on the chosen server: DIR_* parameters are per instance
*                                                              [v0.6]
  DATA: lv_name TYPE string,
        lv_path TYPE string,
        lv_msg  TYPE c LENGTH 200.

  CLEAR cv_path.
  lv_name = iv_dirname.
  IF gv_dest IS INITIAL.
    CALL FUNCTION 'Z_PTP_SVAL_DIR_PATH'
      EXPORTING iv_name = lv_name
      IMPORTING ev_path = lv_path.
  ELSE.
    CALL FUNCTION 'Z_PTP_SVAL_DIR_PATH'
      DESTINATION gv_dest
      EXPORTING  iv_name = lv_name
      IMPORTING  ev_path = lv_path
      EXCEPTIONS system_failure        = 1 MESSAGE lv_msg
                 communication_failure = 2 MESSAGE lv_msg
                 OTHERS                = 3.
    IF sy-subrc <> 0.
      MESSAGE |Server { p_asrv } cannot be reached: { lv_msg }| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.
  cv_path = lv_path.
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

* paths of the server chosen on the screen                    [v0.6]
  PERFORM f_dest_from_screen.
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
        lt_list  TYPE gtt_fili,
        lv_rc    TYPE sysubrc,                                  " [v0.6]
        lt_ret   TYPE STANDARD TABLE OF ddshretval.

* server chosen on the screen                                [v0.6]
  PERFORM f_dest_from_screen.
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
*   DIR_HOME of the chosen server                            [v0.6]
    PERFORM f_dir_path USING 'DIR_HOME' CHANGING lv_value.
    lv_dir = lv_value.
    lv_sep = COND #( WHEN lv_dir CA '\' THEN '\' ELSE '/' ).
  ENDIF.
  IF lv_dir IS INITIAL.
    MESSAGE 'Type a directory in the file field, then press F4' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

* files of the directory, on the chosen server               [v0.6]
  PERFORM f_srv_dir_list USING lv_dir CHANGING lt_list lv_rc.
  CASE lv_rc.
    WHEN 0.
    WHEN 4.
      MESSAGE |No authorization to read directory { lv_dir } (S_DATASET)| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    WHEN 7.
      MESSAGE |Directory { lv_dir } is empty| TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    WHEN OTHERS.
      MESSAGE |Directory { lv_dir } cannot be read (return code { lv_rc }) - check the path in AL11|
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
        lv_exists TYPE abap_bool,                              " [v0.6]
        lv_rc     TYPE sysubrc,
        lv_msg    TYPE bapi_msg.

* existing file: ask before overwriting
  IF p_ovr = abap_false.
    PERFORM f_srv_exists USING gv_target CHANGING lv_exists.     " [v0.6]
    IF lv_exists = abap_true.
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

* written on the chosen server                                [v0.6]
  PERFORM f_srv_write USING gv_target CHANGING lv_rc lv_msg.
  IF lv_rc <> 0.
    MESSAGE lv_msg TYPE 'E'.
  ENDIF.

* the full path is what the reading programs need               [v0.2]
  MESSAGE |File copied: { gv_len } bytes to { gv_target } on server { p_asrv } - enter this | &&
          |path with "Application server" in the migration or batch copy program| TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_SERVER_FILE                                  [v0.5]
*&      Download: files of the directory typed in P_DFILE (a path, an
*&      AL11 directory name, or DIR_HOME when empty); the file chosen
*&      goes in P_DFILE with its full path.
*&---------------------------------------------------------------------*
FORM f_f4_server_file.
  DATA: lt_dynp  TYPE STANDARD TABLE OF dynpread,
        lv_path  TYPE string,
        lv_dir   TYPE eps2filnam,
        lv_dirs  TYPE string,
        lv_sep   TYPE c,
        lt_list  TYPE gtt_fili,
        lv_rc    TYPE sysubrc,                                  " [v0.6]
        lt_ret   TYPE STANDARD TABLE OF ddshretval.

* server chosen on the screen                                [v0.6]
  PERFORM f_dest_from_screen.
* value typed but not yet transferred to the program
  lt_dynp = VALUE #( ( fieldname = 'P_DFILE' ) ).
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING  dyname     = sy-repid
               dynumb     = sy-dynnr
    TABLES     dynpfields = lt_dynp
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc = 0.
    READ TABLE lt_dynp INTO DATA(ls_dynp) INDEX 1.
    IF sy-subrc = 0.
      p_dfile = condense( CONV string( ls_dynp-fieldvalue ) ).
    ENDIF.
  ENDIF.

  lv_path = p_dfile.
  IF lv_path CA '/\'.
*   a path: the directory is everything before the last separator, or
*   the path itself when it ends with a separator
    FIND ALL OCCURRENCES OF REGEX '[\\/]' IN lv_path MATCH OFFSET DATA(lv_off).
    lv_sep = lv_path+lv_off(1).
    lv_dirs = COND #( WHEN lv_off = 0 THEN lv_sep
                      ELSE substring( val = lv_path len = lv_off ) ).
  ELSE.
*   an AL11 directory name, or DIR_HOME when the field is empty
    DATA(lv_name) = COND string( WHEN lv_path IS INITIAL THEN `DIR_HOME` ELSE lv_path ).
    PERFORM f_dir_path USING lv_name CHANGING lv_dirs.
    lv_sep = COND #( WHEN lv_dirs CA '\' THEN '\' ELSE '/' ).
  ENDIF.
  IF lv_dirs IS INITIAL.
    MESSAGE 'Type a directory (path or AL11 name) in the field, then press F4' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
* without the trailing separator for the listing
  IF strlen( lv_dirs ) > 1 AND substring( val = lv_dirs off = strlen( lv_dirs ) - 1 len = 1 ) = lv_sep.
    lv_dirs = substring( val = lv_dirs len = strlen( lv_dirs ) - 1 ).
  ENDIF.
  lv_dir = lv_dirs.

* files of the directory, on the chosen server               [v0.6]
  PERFORM f_srv_dir_list USING lv_dir CHANGING lt_list lv_rc.
  CASE lv_rc.
    WHEN 0.
    WHEN 4.
      MESSAGE |No authorization to read directory { lv_dirs } (S_DATASET)| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    WHEN 7.
      MESSAGE |Directory { lv_dirs } is empty| TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    WHEN OTHERS.
      MESSAGE |Directory { lv_dirs } cannot be read (return code { lv_rc }) - check the path in AL11|
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDCASE.

  SORT lt_list BY name.
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'NAME'
               window_title    = CONV char40( |Files in { lv_dirs }| )
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
    p_dfile = COND #( WHEN lv_dirs = lv_sep THEN |{ lv_sep }{ ls_ret-fieldval }|
                      ELSE |{ lv_dirs }{ lv_sep }{ ls_ret-fieldval }| ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_PC_FOLDER                                    [v0.5]
*&      Download: folder of the PC, through the SAP GUI folder dialog.
*&---------------------------------------------------------------------*
FORM f_f4_pc_folder.
  DATA lv_folder TYPE string.
  cl_gui_frontend_services=>directory_browse(
    EXPORTING  window_title    = 'Folder on the PC'
    CHANGING   selected_folder = lv_folder
    EXCEPTIONS OTHERS          = 1 ).
  IF sy-subrc = 0 AND lv_folder IS NOT INITIAL.
    p_ddir = lv_folder.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_SERVER                                     [v0.5]
*&      Download: the server file is read in binary mode into GT_BIN;
*&      GV_LEN = number of bytes.
*&---------------------------------------------------------------------*
FORM f_read_server.
  DATA: lv_rc  TYPE sysubrc,                                    " [v0.6]
        lv_msg TYPE bapi_msg.

  IF sy-batch = abap_true.
    MESSAGE 'Run this report in dialog: the PC folder needs the SAP GUI' TYPE 'E'.
  ENDIF.

  CLEAR: gt_bin, gv_len.
* read on the chosen server                                    [v0.6]
  PERFORM f_srv_read USING p_dfile CHANGING lv_rc lv_msg.
  IF lv_rc <> 0.
    MESSAGE lv_msg TYPE 'E'.
  ENDIF.

  IF gv_len = 0.
    MESSAGE |File { p_dfile } on the server is empty| TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DOWNLOAD                                        [v0.5]
*&      Download: GT_BIN written to the PC folder P_DDIR under the name
*&      of the server file, as is (BIN). A file of the same name on the
*&      PC is replaced after a confirmation, unless P_DOVR is ticked.
*&---------------------------------------------------------------------*
FORM f_download.
  DATA: lv_file   TYPE string,
        lv_target TYPE string,
        lv_psep   TYPE c,
        lv_exists TYPE abap_bool,
        lv_answer TYPE c.

* name of the server file, without its directory
  lv_file = p_dfile.
  FIND ALL OCCURRENCES OF REGEX '[\\/]' IN lv_file MATCH OFFSET DATA(lv_off).
  IF sy-subrc = 0.
    lv_file = substring( val = lv_file off = lv_off + 1 ).
  ENDIF.

* PC path: folder + separator of the PC + name
  cl_gui_frontend_services=>get_file_separator(
    CHANGING   file_separator = lv_psep
    EXCEPTIONS OTHERS         = 1 ).
  IF sy-subrc <> 0 OR lv_psep IS INITIAL.
    lv_psep = '\'.
  ENDIF.
  lv_target = p_ddir.
  IF substring( val = lv_target off = strlen( lv_target ) - 1 len = 1 ) <> lv_psep.
    lv_target = lv_target && lv_psep.
  ENDIF.
  lv_target = lv_target && lv_file.

* existing file on the PC: ask before replacing it
  IF p_dovr = abap_false.
    cl_gui_frontend_services=>file_exist(
      EXPORTING  file   = lv_target
      RECEIVING  result = lv_exists
      EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc = 0 AND lv_exists = abap_true.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING titlebar       = 'File exists on the PC'
                  text_question  = |{ lv_target } already exists. Replace it?|
                  text_button_1  = 'Replace'
                  text_button_2  = 'Cancel'
                  default_button = '2'
        IMPORTING answer         = lv_answer.
      IF lv_answer <> '1'.
        MESSAGE 'Download cancelled: the PC file was not changed' TYPE 'S' DISPLAY LIKE 'W'.
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.

  cl_gui_frontend_services=>gui_download(
    EXPORTING  bin_filesize = gv_len
               filename     = lv_target
               filetype     = 'BIN'
    CHANGING   data_tab     = gt_bin
    EXCEPTIONS OTHERS       = 1 ).
  IF sy-subrc <> 0.
    MESSAGE |Cannot write { lv_target } on the PC (rc={ sy-subrc })| TYPE 'E'.
  ENDIF.

  MESSAGE |File downloaded: { gv_len } bytes from { p_dfile } (server { p_asrv }) to { lv_target }|
          TYPE 'S'.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_OWN_SERVER                                      [v0.6]
*&      Instance of the current session (profile parameter
*&      rdisp/myname, the name shown in SM51).
*&---------------------------------------------------------------------*
FORM f_own_server.
  DATA lv_value TYPE spfl_parameter_value.
  cl_spfl_profile_parameter=>get_value( EXPORTING name  = 'rdisp/myname'
                                        IMPORTING value = lv_value ).
  gv_own = lv_value.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_SET_DEST                                        [v0.6]
*&      RFC destination of the chosen server: blank for the current
*&      server (the modules are then called locally).
*&---------------------------------------------------------------------*
FORM f_set_dest.
  IF gv_own IS INITIAL.
    PERFORM f_own_server.
  ENDIF.
  gv_dest = COND #( WHEN p_asrv IS INITIAL OR p_asrv = gv_own THEN space ELSE p_asrv ).
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_DEST_FROM_SCREEN                                [v0.6]
*&      F4 helps run before the screen values reach the program: the
*&      server typed in P_ASRV is read from the screen first.
*&---------------------------------------------------------------------*
FORM f_dest_from_screen.
  DATA lt_dynp TYPE STANDARD TABLE OF dynpread.
  lt_dynp = VALUE #( ( fieldname = 'P_ASRV' ) ).
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING  dyname     = sy-repid
               dynumb     = sy-dynnr
    TABLES     dynpfields = lt_dynp
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc = 0.
    READ TABLE lt_dynp INTO DATA(ls_dynp) INDEX 1.
    IF sy-subrc = 0.
      p_asrv = condense( CONV string( ls_dynp-fieldvalue ) ).
    ENDIF.
  ENDIF.
  PERFORM f_set_dest.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_ASRV                                         [v0.6]
*&      Value list of the active application servers (SM51).
*&---------------------------------------------------------------------*
FORM f_f4_asrv.
  TYPES: BEGIN OF lty_srv,
           name TYPE msxxlist-name,
           host TYPE msxxlist-host,
         END OF lty_srv.
  DATA: lt_list TYPE STANDARD TABLE OF msxxlist,
        lt_srv  TYPE STANDARD TABLE OF lty_srv,
        lt_ret  TYPE STANDARD TABLE OF ddshretval.

  CALL FUNCTION 'TH_SERVER_LIST'
    TABLES     list           = lt_list
    EXCEPTIONS no_server_list = 1
               OTHERS         = 2.
  IF sy-subrc <> 0 OR lt_list IS INITIAL.
    MESSAGE 'The list of application servers cannot be read (SM51)' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.
  lt_srv = CORRESPONDING #( lt_list ).
  SORT lt_srv BY name.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'NAME'
               dynpprog        = sy-repid
               dynpnr          = sy-dynnr
               dynprofield     = 'P_ASRV'
               window_title    = 'Application servers (SM51)'
               value_org       = 'S'
    TABLES     value_tab       = lt_srv
               return_tab      = lt_ret
    EXCEPTIONS OTHERS          = 1.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_CHECK_ASRV                                      [v0.6]
*&      The chosen server must be an active instance of this system.
*&---------------------------------------------------------------------*
FORM f_check_asrv.
  DATA lt_list TYPE STANDARD TABLE OF msxxlist.

  CALL FUNCTION 'TH_SERVER_LIST'
    TABLES     list           = lt_list
    EXCEPTIONS no_server_list = 1
               OTHERS         = 2.
  CHECK sy-subrc = 0 AND lt_list IS NOT INITIAL.     " list unavailable: the RFC call will tell
  READ TABLE lt_list TRANSPORTING NO FIELDS WITH KEY name = p_asrv.
  IF sy-subrc <> 0.
    MESSAGE |Application server { p_asrv } is not active in this system (SM51) - F4 lists them|
            TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Forms F_SRV_*                                            [v0.6]
*&      File access on the chosen server: the modules of function group
*&      ZPTP_SVAL_FILE, called locally (current server) or by RFC with
*&      DESTINATION <instance>. A failed RFC call is returned as an
*&      error with its message.
*&---------------------------------------------------------------------*
FORM f_srv_dir_list USING    iv_dir  TYPE eps2filnam
                    CHANGING ct_list TYPE gtt_fili
                             cv_rc   TYPE sysubrc.
* the module returns the file names (STRING_TABLE)          [v0.6]
  DATA: lt_names TYPE string_table,
        lv_msg   TYPE c LENGTH 200.
  CLEAR: ct_list, cv_rc.
  IF gv_dest IS INITIAL.
    CALL FUNCTION 'Z_PTP_SVAL_DIR_LIST'
      EXPORTING iv_dir   = iv_dir
      IMPORTING ev_subrc = cv_rc
                et_names = lt_names.
  ELSE.
    CALL FUNCTION 'Z_PTP_SVAL_DIR_LIST'
      DESTINATION gv_dest
      EXPORTING  iv_dir   = iv_dir
      IMPORTING  ev_subrc = cv_rc
                 et_names = lt_names
      EXCEPTIONS system_failure        = 1 MESSAGE lv_msg
                 communication_failure = 2 MESSAGE lv_msg
                 OTHERS                = 3.
    IF sy-subrc <> 0.
      cv_rc = 99.
      MESSAGE |Server { p_asrv } cannot be reached: { lv_msg }| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDIF.
  LOOP AT lt_names INTO DATA(lv_name).
    APPEND VALUE eps2fili( name = lv_name ) TO ct_list.
  ENDLOOP.
ENDFORM.

FORM f_srv_exists USING    iv_path   TYPE string
                  CHANGING cv_exists TYPE abap_bool.
  DATA: lv_ex  TYPE xfeld,
        lv_msg TYPE c LENGTH 200.
  CLEAR cv_exists.
  IF gv_dest IS INITIAL.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_EXISTS'
      EXPORTING iv_path   = iv_path
      IMPORTING ev_exists = lv_ex.
  ELSE.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_EXISTS'
      DESTINATION gv_dest
      EXPORTING  iv_path   = iv_path
      IMPORTING  ev_exists = lv_ex
      EXCEPTIONS system_failure        = 1 MESSAGE lv_msg
                 communication_failure = 2 MESSAGE lv_msg
                 OTHERS                = 3.
    IF sy-subrc <> 0.
      MESSAGE |Server { p_asrv } cannot be reached: { lv_msg }| TYPE 'E'.
    ENDIF.
  ENDIF.
  cv_exists = lv_ex.
ENDFORM.

FORM f_srv_read USING    iv_path TYPE string
                CHANGING cv_rc   TYPE sysubrc
                         cv_msg  TYPE bapi_msg.
  DATA: lv_len TYPE int4,
        lv_rfc TYPE c LENGTH 200.
  CLEAR: gt_bin, gv_len, cv_rc, cv_msg.
  IF gv_dest IS INITIAL.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_READ'
      EXPORTING iv_path    = iv_path
      IMPORTING ev_length  = lv_len
                ev_subrc   = cv_rc
                ev_message = cv_msg
                et_data    = gt_bin.
  ELSE.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_READ'
      DESTINATION gv_dest
      EXPORTING  iv_path    = iv_path
      IMPORTING  ev_length  = lv_len
                 ev_subrc   = cv_rc
                 ev_message = cv_msg
                 et_data    = gt_bin
      EXCEPTIONS system_failure        = 1 MESSAGE lv_rfc
                 communication_failure = 2 MESSAGE lv_rfc
                 OTHERS                = 3.
    IF sy-subrc <> 0.
      cv_rc  = 99.
      cv_msg = |Server { p_asrv } cannot be reached: { lv_rfc }|.
    ENDIF.
  ENDIF.
  gv_len = lv_len.
ENDFORM.

FORM f_srv_write USING    iv_path TYPE string
                 CHANGING cv_rc   TYPE sysubrc
                          cv_msg  TYPE bapi_msg.
  DATA: lv_len TYPE int4,
        lv_rfc TYPE c LENGTH 200.
  CLEAR: cv_rc, cv_msg.
  lv_len = gv_len.
  IF gv_dest IS INITIAL.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_WRITE'
      EXPORTING iv_path    = iv_path
                iv_length  = lv_len
                it_data    = gt_bin
      IMPORTING ev_subrc   = cv_rc
                ev_message = cv_msg.
  ELSE.
    CALL FUNCTION 'Z_PTP_SVAL_FILE_WRITE'
      DESTINATION gv_dest
      EXPORTING  iv_path    = iv_path
                 iv_length  = lv_len
                 it_data    = gt_bin
      IMPORTING  ev_subrc   = cv_rc
                 ev_message = cv_msg
      EXCEPTIONS system_failure        = 1 MESSAGE lv_rfc
                 communication_failure = 2 MESSAGE lv_rfc
                 OTHERS                = 3.
    IF sy-subrc <> 0.
      cv_rc  = 99.
      cv_msg = |Server { p_asrv } cannot be reached: { lv_rfc }|.
    ENDIF.
  ENDIF.
ENDFORM.
