*&---------------------------------------------------------------------*
*& Function group ZPTP_SVAL_FILE
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : File access on a chosen application server (RFC)
*& Version : v0.2
*& Package : ZPTP_SPLIT_VAL
*&
*& ABAP file statements (OPEN / READ / TRANSFER / CLOSE DATASET) always
*& work on the application server of the current session. These
*& remote-enabled function modules do the file work on the server they
*& are called on: ZPTP_SPLIT_VAL_MIG_UPLOAD calls them with
*&   CALL FUNCTION ... DESTINATION <instance name>
*& where the instance name is one of transaction SM51 (TH_SERVER_LIST),
*& e.g. hbmapp02_HBM_00. An instance name of the same system is a valid
*& RFC destination without any SM59 entry. Called without DESTINATION
*& they work on the current server.
*&
*& Create in SE37 / SE80:
*&   - function group ZPTP_SVAL_FILE, package ZPTP_SPLIT_VAL;
*&   - the five function modules below, processing type
*&     "Remote-Enabled Module", every parameter "Pass by value", with the
*&     interface given in the comment block of each module.
*&
*& v0.2: no TABLES parameters (obsolete): the tables are Export / Import
*& parameters typed with the standard table types SOLIX_TAB (file
*& content) and STRING_TABLE (file names), passed by value.
*&
*& Authorizations: the caller needs S_RFC (RFC_TYPE = FUGR, RFC_NAME =
*& ZPTP_SVAL_FILE, ACTVT 16); the file access itself is checked on the
*& target server with S_DATASET as usual.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Function module Z_PTP_SVAL_DIR_PATH
*&   Path of an AL11 directory name on this server: profile parameter
*&   DIR_* (instance-specific) or user-defined directory (USER_DIR).
*&---------------------------------------------------------------------*
FUNCTION z_ptp_sval_dir_path.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_NAME) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_PATH) TYPE  STRING
*"----------------------------------------------------------------------
  DATA: lv_name  TYPE spfl_parameter_name,
        lv_value TYPE spfl_parameter_value,
        lv_dir   TYPE string.

  CLEAR ev_path.
  lv_dir = to_upper( condense( val = iv_name ) ).
  IF lv_dir IS INITIAL.
    RETURN.
  ENDIF.

* SAP directories of AL11 are profile parameters (DIR_HOME, ...)
  IF lv_dir CP 'DIR_*'.
    lv_name = lv_dir.
    cl_spfl_profile_parameter=>get_value( EXPORTING name  = lv_name
                                          IMPORTING value = lv_value ).
    ev_path = lv_value.
    IF ev_path IS NOT INITIAL.
      RETURN.
    ENDIF.
  ENDIF.

* user-defined directories of AL11
  SELECT SINGLE dirname FROM user_dir INTO @DATA(lv_udir)
    WHERE aliass = @lv_dir.
  IF sy-subrc = 0.
    ev_path = lv_udir.
  ENDIF.
ENDFUNCTION.

*&---------------------------------------------------------------------*
*& Function module Z_PTP_SVAL_DIR_LIST
*&   Names of the files of a directory of this server
*&   (EPS2_GET_DIRECTORY_LISTING).
*&   EV_SUBRC = return code of EPS2_GET_DIRECTORY_LISTING (0 = OK,
*&   4 no authorization, 7 empty directory, others: cannot be read).
*&---------------------------------------------------------------------*
FUNCTION z_ptp_sval_dir_list.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_DIR) TYPE  EPS2FILNAM
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  SYSUBRC
*"     VALUE(ET_NAMES) TYPE  STRING_TABLE
*"----------------------------------------------------------------------
  DATA lt_list TYPE STANDARD TABLE OF eps2fili.

  CLEAR et_names.
  CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
    EXPORTING  iv_dir_name            = iv_dir
    TABLES     dir_list               = lt_list
    EXCEPTIONS invalid_eps_subdir     = 1
               sapgparam_failed       = 2
               build_directory_failed = 3
               no_authorization       = 4
               read_directory_failed  = 5
               too_many_read_errors   = 6
               empty_directory_list   = 7
               OTHERS                 = 8.
  ev_subrc = sy-subrc.
  LOOP AT lt_list INTO DATA(ls_list).
    APPEND CONV string( ls_list-name ) TO et_names.
  ENDLOOP.
ENDFUNCTION.

*&---------------------------------------------------------------------*
*& Function module Z_PTP_SVAL_FILE_EXISTS
*&   X when the file exists on this server and can be opened.
*&---------------------------------------------------------------------*
FUNCTION z_ptp_sval_file_exists.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PATH) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_EXISTS) TYPE  XFELD
*"----------------------------------------------------------------------
  CLEAR ev_exists.
  OPEN DATASET iv_path FOR INPUT IN BINARY MODE.
  IF sy-subrc = 0.
    CLOSE DATASET iv_path.
    ev_exists = abap_true.
  ENDIF.
ENDFUNCTION.

*&---------------------------------------------------------------------*
*& Function module Z_PTP_SVAL_FILE_READ
*&   Reads a file of this server in binary mode. EV_LENGTH = number of
*&   bytes. EV_SUBRC <> 0: the file cannot be opened (EV_MESSAGE).
*&---------------------------------------------------------------------*
FUNCTION z_ptp_sval_file_read.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PATH) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_LENGTH) TYPE  INT4
*"     VALUE(EV_SUBRC) TYPE  SYSUBRC
*"     VALUE(EV_MESSAGE) TYPE  BAPI_MSG
*"     VALUE(ET_DATA) TYPE  SOLIX_TAB
*"----------------------------------------------------------------------
  DATA: ls_line TYPE solix,
        lv_got  TYPE i.

  CLEAR: et_data, ev_length, ev_subrc, ev_message.

  OPEN DATASET iv_path FOR INPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    ev_subrc   = 4.
    ev_message = |Cannot read { iv_path } on server { sy-host } (path or authorization)|.
    RETURN.
  ENDIF.
  DO.
    CLEAR: ls_line, lv_got.
    READ DATASET iv_path INTO ls_line-line ACTUAL LENGTH lv_got.
    IF lv_got > 0.
      APPEND ls_line TO et_data.
      ev_length = ev_length + lv_got.
    ENDIF.
*   sy-subrc 4: end of the file (the last piece may be shorter)
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.
  ENDDO.
  CLOSE DATASET iv_path.
ENDFUNCTION.

*&---------------------------------------------------------------------*
*& Function module Z_PTP_SVAL_FILE_WRITE
*&   Writes IT_DATA (IV_LENGTH bytes) to a file of this server in binary
*&   mode, replacing it when it exists. EV_SUBRC <> 0: the file cannot be
*&   written (EV_MESSAGE).
*&---------------------------------------------------------------------*
FUNCTION z_ptp_sval_file_write.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PATH) TYPE  STRING
*"     VALUE(IV_LENGTH) TYPE  INT4
*"     VALUE(IT_DATA) TYPE  SOLIX_TAB
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  SYSUBRC
*"     VALUE(EV_MESSAGE) TYPE  BAPI_MSG
*"----------------------------------------------------------------------
  DATA: lv_left  TYPE i,
        lv_chunk TYPE i.

  CLEAR: ev_subrc, ev_message.

  OPEN DATASET iv_path FOR OUTPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    ev_subrc   = 4.
    ev_message = |Cannot write { iv_path } on server { sy-host } (path or authorization)|.
    RETURN.
  ENDIF.

  lv_left = iv_length.
  LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_line>).
    IF lv_left <= 0.
      EXIT.
    ENDIF.
    lv_chunk = nmin( val1 = lv_left val2 = 255 ).
    TRANSFER <ls_line>-line TO iv_path LENGTH lv_chunk.
    lv_left = lv_left - lv_chunk.
  ENDLOOP.
  CLOSE DATASET iv_path.
ENDFUNCTION.
