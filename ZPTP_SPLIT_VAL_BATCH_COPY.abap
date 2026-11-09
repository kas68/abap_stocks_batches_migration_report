*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_BATCH_COPY
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Copy of batch master data from the source plant to the
*&           target plant, enriched with the valuation type of a file
*& Version : v1.0
*& Package : ZPTP_SPLIT_VAL
*&
*&---------------------------------------------------------------------*
*& Description
*&---------------------------------------------------------------------*
*& v1.0 - the run is driven by the batches of the source plant, not by
*& the file. Every batch of the source plant (default 8P01, MCHA, not
*& flagged for deletion, within S_MATNR / S_CHARG) is extended to the
*& target plant (default 8Q01): the batch data at plant level is read in
*& the source plant (BAPI_BATCH_GET_DETAIL) and the batch is created in
*& the target plant (BAPI_BATCH_CREATE) with the same attributes. No
*& stock movement is posted. The valuation type depends on the material
*& in the target plant:
*&   - split-valuated (MBEW header row with a valuation category BWTTY,
*&     same test as ZPTP_SPLIT_VAL_MIG): the valuation type is taken from
*&     the file line with the same Material + Batch. No such line: error,
*&     the batch is not copied;
*&   - not split-valuated: the batch is copied without valuation type; a
*&     valuation type given by the file is ignored (noted in the message).
*&
*& The CSV file (separator ';', UTF-8 or Windows-1252) has one header
*& line and item lines                              [v0.3, was .xlsx]
*&
*&     MATERIAL;BATCH;VALUATION TYPE
*&
*& It only supplies the valuation types of the split-valuated materials.
*& Batch matching (v0.9): a numeric batch of the file is normalised with
*& leading zeros to 10 characters and matched first in that form against
*& the source batches; when that fails, the form without leading zeros
*& is tried. Non-numeric batches are compared as written (upper case).
*&
*& Checks per batch (status E, batch not copied, otherwise):
*&   - the material is extended to the target plant and batch-managed in
*&     both plants (MARC-XCHPF or MARA-XCHPF);
*&   - split-valuated material: a file line exists for the batch, carries
*&     a valuation type, the valuation type exists in the target plant
*&     (MBEW-BWTAR), and the file gives only one valuation type for it;
*&   - a batch already existing in the target plant is not recreated:
*&     status A when nothing is to do (same valuation type, or material
*&     not split-valuated), E when its valuation type differs from the
*&     file (a batch carries one valuation type).
*& File lines that cannot be used are listed as errors too: material
*& number not convertible, material or batch missing, batch not found
*& among the source batches selected (does not exist, flagged for
*& deletion, or outside S_CHARG).
*&
*& Run modes (v0.2):
*&   - Online (P_ONL, default): the file is read and checked, then the
*&     ALV lists every item. A double-click on one item asks for
*&     confirmation and creates that batch (BAPI_BATCH_CREATE + commit).
*&     The line turns green when the batch is created (or already exists
*&     with the same valuation type), red on an error. Lines rejected by
*&     the checks are red from the start. P_TEST does not apply.
*&   v0.8: the online ALV has its own GUI status ZBCPY_ALV (SE41, copy
*&     of SAPLKKBL / STANDARD_FULLSCREEN + function POST). The user ticks
*&     one or several rows and presses "Post"; created rows turn green,
*&     failed rows red. Double-click no longer creates anything.
*&   - Statuses (v0.8): R ready, A batch already in the target plant with
*&     the valuation type of the file (blue, nothing to do), S created
*&     (green), E error (red), T simulated (yellow). R / A / E are known
*&     before posting; S_STAT restricts or excludes them (for example
*&     exclude A to hide the batches already extended).
*&   - Background (P_BGD): started with F8 from the screen, the report
*&     schedules itself as a background job started immediately (v0.7)
*&     with the same selection, and shows the job name and number (SM37);
*&     the file must then be on the application server. In the job
*&     every item is processed in one run, as in v0.1;
*&     P_TEST (default on) runs all checks without creating anything. Can
*&     run as a job (SM36) with a file on the application server.
*& The file is read from the PC (dialog only) or from the application
*& server. Result: ALV list (spool in a job), no database log.
*&
*&---------------------------------------------------------------------*
*& Assumptions
*&---------------------------------------------------------------------*
*& - Line 1 is the header and is skipped. Fields after the third are
*&   ignored. The file may hold no item line: then only the batches of
*&   materials not split-valuated in the target plant can be copied.
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
  gc_st_ok    TYPE c VALUE 'S',     " batch created in the target plant
  gc_st_err   TYPE c VALUE 'E',
  gc_st_test  TYPE c VALUE 'T',     " simulation, not created
  gc_st_open  TYPE c VALUE 'R',     " ready, not processed yet [v0.2, 'R' v0.8]
  gc_st_exist TYPE c VALUE 'A',     " already in the target plant, same valuation type [v0.8]
  gc_status   TYPE sy-pfkey VALUE 'ZBCPY_ALV',   " GUI status of the online ALV (SE41) [v0.8]
  gc_post     TYPE sy-ucomm VALUE 'POST'.        " its function code [v0.8]
CONSTANTS:
  gc_xchpf   TYPE xchpf VALUE 'X',
  gc_sep     TYPE c VALUE ';'.         " field separator of the CSV file [v0.3]

* file line                                                     [v1.0]
TYPES: BEGIN OF gty_file,
         line  TYPE i,
         matnr TYPE matnr,
         charg TYPE charg_d,             " as in the file (upper case)
         bwtar TYPE bwtar_d,
         bad   TYPE abap_bool,
         msg   TYPE bapi_msg,
         id    TYPE i,                   " source batch it was matched to
       END OF gty_file,
       gtt_file TYPE STANDARD TABLE OF gty_file WITH DEFAULT KEY.

* one item per source batch, plus one per unusable file line   [v1.0]
TYPES: BEGIN OF gty_item,
         id    TYPE i,                   " item number               [v1.0]
         line  TYPE i,                   " file line, 0 = not in the file
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
         split TYPE abap_bool,           " split-valuated in the target plant [v1.0]
         multi TYPE abap_bool,           " several valuation types in the file [v1.0]
         bad   TYPE abap_bool,
         msg   TYPE bapi_msg,
         note  TYPE bapi_msg,            " information, e.g. batch completed [v0.4]
         pstat TYPE c LENGTH 1,          " status before posting: R / A / E [v0.8]
         pmsg  TYPE bapi_msg,            " its message [v0.8]
       END OF gty_item,
       gtt_item TYPE SORTED TABLE OF gty_item WITH UNIQUE KEY id.

TYPES: BEGIN OF gty_out,
         sel     TYPE c LENGTH 1,        " row ticked for posting (online) [v0.8]
         status  TYPE c LENGTH 1,
         id      TYPE i,                 " item number, hidden [v1.0]
         line    TYPE i,
         matnr   TYPE matnr,
         charg   TYPE charg_d,
         bwtar   TYPE bwtar_d,
         split   TYPE abap_bool,         " split-valuated in the target plant [v1.0]
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

TYPES: BEGIN OF gty_tbat,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,
       END OF gty_tbat,
       gtt_tbat TYPE SORTED TABLE OF gty_tbat WITH UNIQUE KEY matnr charg.
TYPES: BEGIN OF gty_vt,
         matnr TYPE matnr,
         bwtar TYPE bwtar_d,
       END OF gty_vt,
       gtt_vt TYPE SORTED TABLE OF gty_vt WITH UNIQUE KEY matnr bwtar.

DATA: gt_file  TYPE gtt_file,                                   " [v1.0]
      gt_item  TYPE gtt_item,
      gt_out   TYPE gtt_out,
      gt_marc  TYPE gtt_marc,
      gt_split TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line, " split-valuated in target [v1.0]
      gt_vt    TYPE gtt_vt,         " valuation types of the target plant [v1.0]
      gt_tbat  TYPE gtt_tbat,       " batches already in the target plant [v1.0]
      gv_sim  TYPE abap_bool,          " simulation: background mode with P_TEST [v0.2]
      gv_job  TYPE abap_bool.          " the run was handed over to a background job [v0.7]

* reference fields of the select-options                [v0.8, v1.0]
DATA: gv_sel_stat  TYPE c LENGTH 1,
      gv_sel_matnr TYPE mara-matnr,
      gv_sel_charg TYPE mcha-charg.

*&---------------------------------------------------------------------*
*&  Selection screen
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
* not OBLIGATORY: a required field left empty locks the screen at the
* first radio-button click; checked on execution in F_CHECK_SCREEN [v0.2]
  PARAMETERS: p_wsrc TYPE werks_d DEFAULT '8P01',                  " source plant
              p_wdst TYPE werks_d DEFAULT '8Q01'.                  " target plant
* batches of the source plant to extend (blank = all)          [v1.0]
  SELECT-OPTIONS: s_matnr FOR gv_sel_matnr,
                  s_charg FOR gv_sel_charg.
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
* status known before posting (R ready, A already in target plant,
* E error); exclude values to leave those batches out          [v0.8]
  SELECT-OPTIONS: s_stat FOR gv_sel_stat.
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

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_stat-low.         " [v0.8]
  PERFORM f_f4_status.
AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_stat-high.
  PERFORM f_f4_status.

AT SELECTION-SCREEN.
  PERFORM f_check_screen.

START-OF-SELECTION.
* the online mode needs a user in front of the ALV            [v0.2]
  IF p_onl = abap_true AND sy-batch = abap_true.
    MESSAGE 'The online mode cannot run in background - choose Background' TYPE 'E'.
  ENDIF.
  gv_sim = xsdbool( p_bgd = abap_true AND p_test = abap_true ).

* background mode started from the screen: hand the run over to a
* background job started immediately                        [v0.7]
  IF p_bgd = abap_true AND sy-batch = abap_false.
    PERFORM f_submit_job.
    gv_job = abap_true.
    RETURN.
  ENDIF.

  PERFORM f_read_file.
* source batches drive the run; the file gives the valuation types [v1.0]
  PERFORM f_read_batches.
  PERFORM f_match_file.
  PERFORM f_check_items.
  PERFORM f_file_leftovers.
* status before posting, then the status selection          [v0.8]
  PERFORM f_pre_status.
  DELETE gt_item WHERE pstat NOT IN s_stat.
  IF gt_item IS INITIAL.
    MESSAGE 'No item left after the status selection' TYPE 'S' DISPLAY LIKE 'W'.
    gv_job = abap_true.                         " nothing to display
    RETURN.
  ENDIF.
  IF p_onl = abap_true.
    PERFORM f_prepare_online.
  ELSE.
    PERFORM f_process_items.
  ENDIF.

END-OF-SELECTION.
* nothing to show when the run was handed over to a job      [v0.7]
  IF gv_job = abap_false.
    PERFORM f_display_alv.
  ENDIF.

*&---------------------------------------------------------------------*
*&      Form  F_SUBMIT_JOB                                      [v0.7]
*&      Background mode started in dialog: the report submits itself
*&      with the same selection as a background job (JOB_OPEN, SUBMIT
*&      VIA JOB, JOB_CLOSE with immediate start). The result list goes
*&      to the spool of the job (SM37 -> Spool).
*&      Releasing a job needs the authorization S_BTCH_JOB (RELE); without
*&      it the job stays scheduled and must be released in SM37.
*&---------------------------------------------------------------------*
FORM f_submit_job.
  DATA: lv_jobname  TYPE tbtcjob-jobname VALUE 'ZPTP_SPLIT_VAL_BCPY',
        lv_jobcount TYPE tbtcjob-jobcount,
        lv_rel      TYPE c.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING  jobname          = lv_jobname
    IMPORTING  jobcount         = lv_jobcount
    EXCEPTIONS cant_create_job  = 1
               invalid_job_data = 2
               jobname_missing  = 3
               OTHERS           = 4.
  IF sy-subrc <> 0.
    MESSAGE |Background job could not be created (JOB_OPEN, return code { sy-subrc })| TYPE 'E'.
  ENDIF.

  SUBMIT zptp_split_val_batch_copy
    WITH p_wsrc = p_wsrc
    WITH p_wdst = p_wdst
    WITH s_matnr IN s_matnr                                     " [v1.0]
    WITH s_charg IN s_charg
    WITH p_loc  = space
    WITH p_srv  = abap_true
    WITH p_file = p_file
    WITH p_onl  = space
    WITH p_bgd  = abap_true
    WITH p_test = p_test
    WITH s_stat IN s_stat                                       " [v0.8]
    VIA JOB lv_jobname NUMBER lv_jobcount
    AND RETURN.
  IF sy-subrc <> 0.
    MESSAGE |The report could not be added to job { lv_jobname } (return code { sy-subrc })| TYPE 'E'.
  ENDIF.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING  jobcount             = lv_jobcount
               jobname              = lv_jobname
               strtimmed            = abap_true
    IMPORTING  job_was_released     = lv_rel
    EXCEPTIONS cant_start_immediate = 1
               invalid_startdate    = 2
               jobname_missing      = 3
               job_close_failed     = 4
               job_nosteps          = 5
               job_notex            = 6
               lock_failed          = 7
               invalid_target       = 8
               OTHERS               = 9.
  IF sy-subrc <> 0.
    MESSAGE |Job { lv_jobname } ({ lv_jobcount }) created but not started (return code { sy-subrc }) - | &&
            |release it in SM37| TYPE 'S' DISPLAY LIKE 'W'.
  ELSEIF lv_rel <> abap_true.
    MESSAGE |Job { lv_jobname } ({ lv_jobcount }) scheduled but not released (authorization | &&
            |S_BTCH_JOB) - release it in SM37| TYPE 'S' DISPLAY LIKE 'W'.
  ELSE.
    DATA(lv_sim) = COND string( WHEN p_test = abap_true THEN ` (simulation)` ).
    MESSAGE |Job { lv_jobname } ({ lv_jobcount }) started{ lv_sim } - follow it in SM37, | &&
            |the result list is in its spool| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_f4_file.
* PC: Windows file dialog (CSV and text files, or any file).
* Application server: list of the files of the directory typed in the
* field (DIR_HOME when none), F_F4_SERVER.                [v0.3, v0.6]
  DATA: lt_ftab    TYPE filetable,
        lv_rc      TYPE i,
        lv_usr     TYPE i,
        lt_dynp    TYPE STANDARD TABLE OF dynpread.

* the radio buttons may have been changed without a screen round trip:
* read their current value from the screen
  lt_dynp = VALUE #( ( fieldname = 'P_LOC' ) ( fieldname = 'P_SRV' )
                     ( fieldname = 'P_FILE' ) ).
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
*   directory typed but not yet transferred to the program
    READ TABLE lt_dynp INTO ls_dynp WITH KEY fieldname = 'P_FILE'.
    IF sy-subrc = 0.
      p_file = condense( CONV string( ls_dynp-fieldvalue ) ).
    ENDIF.
  ENDIF.

  IF p_srv = abap_true.
*   F4_DXFILENAME_TOPRECURSION failed on system directories such as
*   /usr ("IDoc internal error"): replaced by a plain file list [v0.6]
    PERFORM f_f4_server.
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
*&      Form  F_F4_SERVER                                       [v0.6]
*&      Files of one application-server directory: the directory part of
*&      the path typed in P_FILE, or DIR_HOME when the field holds no
*&      directory. To go up or elsewhere, type that directory (for
*&      example /usr/sap/trans/) in the field and press F4 again.
*&---------------------------------------------------------------------*
FORM f_f4_server.
  DATA: lv_path  TYPE string,
        lv_dir   TYPE eps2filnam,
        lv_sep   TYPE c,
        lv_value TYPE spfl_parameter_value,
        lt_list  TYPE STANDARD TABLE OF eps2fili,
        lt_ret   TYPE STANDARD TABLE OF ddshretval.

  lv_path = p_file.
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
    p_file = COND #( WHEN substring( val = CONV string( lv_dir ) off = strlen( lv_dir ) - 1 len = 1 ) = lv_sep
                     THEN |{ lv_dir }{ ls_ret-fieldval }|
                     ELSE |{ lv_dir }{ lv_sep }{ ls_ret-fieldval }| ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM f_check_screen.
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
* a job has no SAP GUI: no PC file, no online mode     [v0.2, v0.7]
* (the background mode always runs as a job)
  IF ( sy-ucomm = 'SJOB' OR p_bgd = abap_true ) AND p_loc = abap_true.
    MESSAGE 'Background mode needs a file on the application server - copy it first with ZPTP_SPLIT_VAL_UPLD'
            TYPE 'E'.
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
        ls_file  TYPE gty_file,
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
    CLEAR: ls_file, lv_matnr, lv_charg, lv_bwtar, lt_field.
    SPLIT lv_line AT gc_sep INTO TABLE lt_field.
    READ TABLE lt_field INDEX 1 INTO lv_matnr.
    READ TABLE lt_field INDEX 2 INTO lv_charg.
    READ TABLE lt_field INDEX 3 INTO lv_bwtar.
    CONDENSE: lv_matnr, lv_charg, lv_bwtar.
    IF lv_matnr IS INITIAL AND lv_charg IS INITIAL AND lv_bwtar IS INITIAL.
      CONTINUE.                           " empty row
    ENDIF.

    ls_file-line  = lv_row.
    ls_file-charg = to_upper( lv_charg ).
    ls_file-bwtar = to_upper( lv_bwtar ).
    IF lv_matnr IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING  input        = lv_matnr
        IMPORTING  output       = ls_file-matnr
        EXCEPTIONS length_error = 1
                   OTHERS       = 2.
      IF sy-subrc <> 0.
        ls_file-bad = abap_true.
        ls_file-msg = |Line { lv_row }: material number '{ lv_matnr }' cannot be converted|.
      ENDIF.
    ENDIF.
    IF ls_file-bad = abap_false AND ( ls_file-matnr IS INITIAL OR ls_file-charg IS INITIAL ).
      ls_file-bad = abap_true.
      ls_file-msg = |Line { lv_row }: material and batch are mandatory|.
    ENDIF.
    APPEND ls_file TO gt_file.
  ENDLOOP.
* a file without item line is accepted: only the batches of materials
* not split-valuated in the target plant can then be copied    [v1.0]
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_BATCHES                                    [v1.0]
*&      Batches of the source plant to extend (MCHA, not flagged for
*&      deletion, within S_MATNR / S_CHARG): one item each. Reads at the
*&      same time, for their materials, the batch management of both
*&      plants, the split valuation and the valuation types of the
*&      target plant, and the batches already in the target plant.
*&---------------------------------------------------------------------*
FORM f_read_batches.
  DATA: lt_mat TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line,
        lv_id  TYPE i.

  CLEAR: gt_item, gt_marc, gt_split, gt_vt, gt_tbat.

  SELECT matnr, charg FROM mcha
    WHERE werks =  @p_wsrc
      AND matnr IN @s_matnr
      AND charg IN @s_charg
      AND lvorm =  @space
    ORDER BY matnr, charg
    INTO TABLE @DATA(lt_src).
  IF lt_src IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT lt_src INTO DATA(ls_src).
    lv_id = lv_id + 1.
    INSERT VALUE gty_item( id = lv_id matnr = ls_src-matnr charg = ls_src-charg )
           INTO TABLE gt_item.
    INSERT ls_src-matnr INTO TABLE lt_mat.
  ENDLOOP.

* batch management in both plants
  SELECT c~matnr, c~werks, c~xchpf, a~xchpf AS xchpf_cl
    FROM marc AS c
    INNER JOIN mara AS a ON a~matnr = c~matnr
    FOR ALL ENTRIES IN @lt_mat
    WHERE c~matnr = @lt_mat-table_line
      AND ( c~werks = @p_wsrc OR c~werks = @p_wdst )
    INTO TABLE @DATA(lt_marc).
  LOOP AT lt_marc INTO DATA(ls_m).
    INSERT VALUE gty_marc( matnr    = ls_m-matnr
                           werks    = ls_m-werks
                           batchmgd = xsdbool( ls_m-xchpf = gc_xchpf
                                            OR ls_m-xchpf_cl = gc_xchpf ) )
           INTO TABLE gt_marc.
  ENDLOOP.

* split-valuated in the target plant: the header row (BWTAR blank)
* carries a valuation category, as tested by ZPTP_SPLIT_VAL_MIG
  SELECT matnr FROM mbew
    FOR ALL ENTRIES IN @lt_mat
    WHERE matnr =  @lt_mat-table_line
      AND bwkey =  @p_wdst
      AND bwtar =  @space
      AND bwtty <> @space
    INTO TABLE @gt_split.

* valuation types of the target plant
  SELECT matnr, bwtar FROM mbew
    FOR ALL ENTRIES IN @lt_mat
    WHERE matnr =  @lt_mat-table_line
      AND bwkey =  @p_wdst
      AND bwtar <> @space
    INTO CORRESPONDING FIELDS OF TABLE @gt_vt.

* batches already in the target plant, with their valuation type
  SELECT matnr, charg, bwtar FROM mcha
    FOR ALL ENTRIES IN @lt_mat
    WHERE matnr = @lt_mat-table_line
      AND werks = @p_wdst
    INTO CORRESPONDING FIELDS OF TABLE @gt_tbat.

  LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
    READ TABLE gt_split TRANSPORTING NO FIELDS WITH TABLE KEY table_line = <ls_item>-matnr.
    <ls_item>-split = xsdbool( sy-subrc = 0 ).
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_MATCH_FILE                                      [v1.0]
*&      Each usable file line is attached to one source batch, on
*&      Material + Batch: first with the batch normalised with leading
*&      zeros, then, for the lines still unmatched, without leading
*&      zeros (v0.9 rule). The item takes the file line and its
*&      valuation type; two file lines with different valuation types
*&      for the same batch flag the item (MULTI).
*&---------------------------------------------------------------------*
FORM f_match_file.
  TYPES: BEGIN OF lty_idx,
           matnr TYPE matnr,
           charg TYPE charg_d,
           id    TYPE i,
         END OF lty_idx.
  DATA: lt_idx  TYPE SORTED TABLE OF lty_idx WITH UNIQUE KEY matnr charg,
        lv_try  TYPE charg_d,
        ls_idx  TYPE lty_idx.

  LOOP AT gt_item INTO DATA(ls_item).
    INSERT VALUE lty_idx( matnr = ls_item-matnr charg = ls_item-charg id = ls_item-id )
           INTO TABLE lt_idx.
  ENDLOOP.

* pass 1: normalised batch; pass 2: batch without leading zeros
  DO 2 TIMES.
    DATA(lv_pass) = sy-index.
    LOOP AT gt_file ASSIGNING FIELD-SYMBOL(<ls_file>) WHERE bad = abap_false AND id = 0.
      IF lv_pass = 1.
        PERFORM f_norm_batch USING <ls_file>-charg CHANGING lv_try.
      ELSE.
        PERFORM f_strip_batch USING <ls_file>-charg CHANGING lv_try.
      ENDIF.
      READ TABLE lt_idx INTO ls_idx WITH TABLE KEY matnr = <ls_file>-matnr charg = lv_try.
      CHECK sy-subrc = 0.
      <ls_file>-id = ls_idx-id.

      READ TABLE gt_item ASSIGNING FIELD-SYMBOL(<ls_item>) WITH TABLE KEY id = ls_idx-id.
      IF <ls_item>-line = 0.
        <ls_item>-line  = <ls_file>-line.
        <ls_item>-bwtar = <ls_file>-bwtar.
        IF <ls_file>-charg <> <ls_item>-charg.
          <ls_item>-note = |batch { <ls_file>-charg } of the file matched as { <ls_item>-charg }|.
        ENDIF.
      ELSEIF <ls_file>-bwtar <> <ls_item>-bwtar.
        <ls_item>-multi = abap_true.
      ENDIF.
    ENDLOOP.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_CHECK_ITEMS   (checks per source batch, before creation)
*&      v1.0: split-valuated material -> the valuation type comes from
*&      the file, mandatory; not split-valuated -> copied without one.
*&---------------------------------------------------------------------*
FORM f_check_items.
  DATA: ls_src TYPE gty_marc,
        ls_dst TYPE gty_marc.

  LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<ls_item>) WHERE bad = abap_false.

    READ TABLE gt_marc INTO ls_src
         WITH TABLE KEY matnr = <ls_item>-matnr werks = p_wsrc.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr ALPHA = OUT } is not extended to plant { p_wsrc }|.
      CONTINUE.
    ENDIF.
    READ TABLE gt_marc INTO ls_dst
         WITH TABLE KEY matnr = <ls_item>-matnr werks = p_wdst.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr ALPHA = OUT } is not extended to plant { p_wdst } | &&
                      |- batch not copied|.
      CONTINUE.
    ENDIF.
    IF ls_src-batchmgd = abap_false OR ls_dst-batchmgd = abap_false.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material { <ls_item>-matnr ALPHA = OUT } is not batch-managed in both plants|.
      CONTINUE.
    ENDIF.

    IF <ls_item>-split = abap_false.
*     not split-valuated: copied without valuation type
      IF <ls_item>-bwtar IS NOT INITIAL.
        <ls_item>-note = |{ COND string( WHEN <ls_item>-note IS NOT INITIAL
                                         THEN |{ <ls_item>-note }, | ) }| &&
                         |valuation type { <ls_item>-bwtar } of the file ignored, | &&
                         |material not split-valuated in plant { p_wdst }|.
        CLEAR <ls_item>-bwtar.
      ENDIF.
      CONTINUE.
    ENDIF.

*   split-valuated: the file must give the valuation type
    IF <ls_item>-line = 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material split-valuated in plant { p_wdst } and batch not in the file | &&
                      |- no valuation type, batch not copied|.
      CONTINUE.
    ENDIF.
    IF <ls_item>-multi = abap_true.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Batch given with several valuation types in the file - batch not copied|.
      CONTINUE.
    ENDIF.
    IF <ls_item>-bwtar IS INITIAL.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Material split-valuated in plant { p_wdst }: file line { <ls_item>-line } | &&
                      |has no valuation type - batch not copied|.
      CONTINUE.
    ENDIF.
    READ TABLE gt_vt TRANSPORTING NO FIELDS
         WITH TABLE KEY matnr = <ls_item>-matnr bwtar = <ls_item>-bwtar.
    IF sy-subrc <> 0.
      <ls_item>-bad = abap_true.
      <ls_item>-msg = |Valuation type { <ls_item>-bwtar } does not exist for material | &&
                      |{ <ls_item>-matnr ALPHA = OUT } in plant { p_wdst }|.
      CONTINUE.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_FILE_LEFTOVERS                                  [v1.0]
*&      File lines that were not used are listed as error items: format
*&      errors, and Material + Batch not found among the source batches
*&      of the selection. Lines outside S_MATNR are left out silently.
*&---------------------------------------------------------------------*
FORM f_file_leftovers.
  DATA: lv_id    TYPE i,
        lv_norm  TYPE charg_d,
        lv_strip TYPE charg_d,
        ls_item  TYPE gty_item.

  lv_id = lines( gt_item ).
  LOOP AT gt_file INTO DATA(ls_file) WHERE id = 0.
    CLEAR ls_item.
    IF ls_file-bad = abap_false.
      CHECK ls_file-matnr IN s_matnr.
      PERFORM f_norm_batch  USING ls_file-charg CHANGING lv_norm.
      PERFORM f_strip_batch USING ls_file-charg CHANGING lv_strip.
      CHECK lv_norm IN s_charg OR lv_strip IN s_charg.
      ls_item-msg = |Batch { lv_norm } of material { ls_file-matnr ALPHA = OUT } not found in plant | &&
                    |{ p_wsrc }{ COND string( WHEN lv_strip <> lv_norm THEN | (nor { lv_strip })| ) } | &&
                    |or flagged for deletion - check the batch number in the file|.
    ELSE.
      ls_item-msg = ls_file-msg.
    ENDIF.
    lv_id = lv_id + 1.
    ls_item-id    = lv_id.
    ls_item-line  = ls_file-line.
    ls_item-matnr = ls_file-matnr.
    ls_item-charg = ls_file-charg.
    ls_item-bwtar = ls_file-bwtar.
    ls_item-bad   = abap_true.
    INSERT ls_item INTO TABLE gt_item.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_NORM_BATCH                                      [v0.9]
*&      Numeric batch -> right-aligned, completed with leading zeros to
*&      10 characters (0000000123). Any other value is returned as is.
*&---------------------------------------------------------------------*
FORM f_norm_batch USING    iv_charg TYPE charg_d
                  CHANGING cv_norm  TYPE charg_d.
  cv_norm = iv_charg.
  CONDENSE cv_norm NO-GAPS.
  IF cv_norm IS INITIAL OR cv_norm CN '0123456789 '.
    cv_norm = iv_charg.
    RETURN.
  ENDIF.
  SHIFT cv_norm RIGHT DELETING TRAILING space.
  OVERLAY cv_norm WITH '0000000000'.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_STRIP_BATCH                                     [v0.9]
*&      Numeric batch -> without leading zeros (123). A batch made of
*&      zeros only, or a non-numeric batch, is returned as is.
*&---------------------------------------------------------------------*
FORM f_strip_batch USING    iv_charg TYPE charg_d
                   CHANGING cv_strip TYPE charg_d.
  cv_strip = iv_charg.
  CONDENSE cv_strip NO-GAPS.
  IF cv_strip IS INITIAL OR cv_strip CN '0123456789 '.
    cv_strip = iv_charg.
    RETURN.
  ENDIF.
  SHIFT cv_strip LEFT DELETING LEADING '0'.
  IF cv_strip IS INITIAL.
    cv_strip = iv_charg.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PRE_STATUS                                [v0.8, v1.0]
*&      Status of each item before posting, used by the status selection:
*&        E  rejected by the checks, or batch already in the target plant
*&           with another (or no) valuation type than the file;
*&        A  batch already in the target plant, nothing to do (same
*&           valuation type, or material not split-valuated);
*&        R  ready to be posted.
*&---------------------------------------------------------------------*
FORM f_pre_status.
  DATA ls_tbat TYPE gty_tbat.

  LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<ls_item>).
    IF <ls_item>-bad = abap_true.
      <ls_item>-pstat = gc_st_err.
      <ls_item>-pmsg  = <ls_item>-msg.
      CONTINUE.
    ENDIF.
    READ TABLE gt_tbat INTO ls_tbat
         WITH TABLE KEY matnr = <ls_item>-matnr charg = <ls_item>-charg.
    IF sy-subrc <> 0.
      <ls_item>-pstat = gc_st_open.
      <ls_item>-pmsg  = |Ready - batch to be created in plant { p_wdst } | &&
                        |{ COND string( WHEN <ls_item>-split = abap_true
                                        THEN |with valuation type { <ls_item>-bwtar }|
                                        ELSE `without valuation type` ) }|.
    ELSEIF <ls_item>-split = abap_false.
      <ls_item>-pstat = gc_st_exist.
      <ls_item>-pmsg  = |Batch already exists in plant { p_wdst }|.
    ELSEIF ls_tbat-bwtar = <ls_item>-bwtar.
      <ls_item>-pstat = gc_st_exist.
      <ls_item>-pmsg  = |Batch already exists in plant { p_wdst } with valuation type { ls_tbat-bwtar }|.
    ELSE.
      <ls_item>-bad   = abap_true.
      <ls_item>-pstat = gc_st_err.
      <ls_item>-pmsg  = COND #( WHEN ls_tbat-bwtar IS INITIAL
                                THEN |Batch exists in plant { p_wdst } without valuation type, | &&
                                     |file gives { <ls_item>-bwtar } - not changed|
                                ELSE |Batch exists in plant { p_wdst } with valuation type | &&
                                     |{ ls_tbat-bwtar }, file gives { <ls_item>-bwtar }| ).
      <ls_item>-msg   = <ls_item>-pmsg.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_STATUS                                       [v0.8]
*&      Value list of the statuses that can be selected (known before
*&      posting). DDIC-typed value table: the help function reads the
*&      field descriptions from the dictionary.
*&---------------------------------------------------------------------*
FORM f_f4_status.
  DATA: lt_val TYPE STANDARD TABLE OF dd07v WITH DEFAULT KEY,
        lt_ret TYPE STANDARD TABLE OF ddshretval.

  lt_val = VALUE #( ( domvalue_l = gc_st_open  ddtext = 'Ready to be posted' )
                    ( domvalue_l = gc_st_exist ddtext = 'Already in the target plant' )
                    ( domvalue_l = gc_st_err   ddtext = 'Error (checks, valuation type)' ) ).

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING  retfield        = 'DOMVALUE_L'
               dynpprog        = sy-repid
               dynpnr          = sy-dynnr
               dynprofield     = 'S_STAT-LOW'
               window_title    = 'Status'
               value_org       = 'S'
    TABLES     value_tab       = lt_val
               return_tab      = lt_ret
    EXCEPTIONS parameter_error = 1
               no_values_found = 2
               OTHERS          = 3.
  IF sy-subrc <> 0.
    MESSAGE 'Status value help could not be displayed' TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PROCESS_ITEMS
*&---------------------------------------------------------------------*
FORM f_process_items.
  DATA ls_out TYPE gty_out.

  LOOP AT gt_item INTO DATA(ls_item).
    CLEAR ls_out.
    PERFORM f_item_to_out USING ls_item CHANGING ls_out.

    IF ls_item-pstat <> gc_st_open.                             " [v0.8]
*     E (checks) or A (already in the target plant): nothing to post
      ls_out-status  = ls_item-pstat.
      ls_out-message = ls_item-pmsg.
    ELSE.
      PERFORM f_copy_batch USING ls_item CHANGING ls_out.
    ENDIF.
    IF ls_item-note IS NOT INITIAL AND ls_out-status <> gc_st_err.
      ls_out-message = |{ ls_out-message } ({ ls_item-note })|.
    ENDIF.
    PERFORM f_set_color CHANGING ls_out.
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_ITEM_TO_OUT                                     [v1.0]
*&---------------------------------------------------------------------*
FORM f_item_to_out USING    is_item TYPE gty_item
                   CHANGING cs_out  TYPE gty_out.
  cs_out-id    = is_item-id.
  cs_out-line  = is_item-line.
  cs_out-matnr = is_item-matnr.
  cs_out-charg = is_item-charg.
  cs_out-bwtar = is_item-bwtar.
  cs_out-split = is_item-split.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_PREPARE_ONLINE                                  [v0.2]
*&      Online mode: one ALV row per item, nothing created yet, with the
*&      status before posting: R ready, A already in plant, E error.
*&---------------------------------------------------------------------*
FORM f_prepare_online.
  DATA ls_out TYPE gty_out.

  LOOP AT gt_item INTO DATA(ls_item).
    CLEAR ls_out.
    PERFORM f_item_to_out USING ls_item CHANGING ls_out.        " [v1.0]
    ls_out-status  = ls_item-pstat.                              " [v0.8]
    ls_out-message = ls_item-pmsg.
    IF ls_item-pstat <> gc_st_err AND ls_item-note IS NOT INITIAL.
      ls_out-message = |{ ls_out-message } ({ ls_item-note })|.
    ENDIF.
    PERFORM f_set_color CHANGING ls_out.
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_SET_STATUS                                      [v0.8]
*&      ALV callback, online mode: GUI status ZBCPY_ALV (SE41), i.e. the
*&      standard ALV toolbar plus the "Post" button.
*&---------------------------------------------------------------------*
FORM f_set_status USING rt_extab TYPE slis_t_extab.
  SET PF-STATUS gc_status EXCLUDING rt_extab.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_USER_COMMAND                                [v0.2, v0.8]
*&      ALV callback, online mode. "Post" (POST): the ticked rows that are
*&      ready (R), or that failed at a previous posting, are created after
*&      one confirmation; each row turns green (created) or red (error).
*&---------------------------------------------------------------------*
FORM f_user_command USING r_ucomm     TYPE sy-ucomm
                          rs_selfield TYPE slis_selfield.
  DATA: ls_item   TYPE gty_item,
        lv_answer TYPE c,
        lv_todo   TYPE i,
        lv_skip   TYPE i,
        lv_ok     TYPE i,
        lv_err    TYPE i,
        lv_text   TYPE string,
        lv_disp   TYPE c.

  CHECK p_onl = abap_true AND r_ucomm = gc_post.

* rows that can be posted: ready, or failed at a previous posting (not
* rejected by the checks)
  LOOP AT gt_out ASSIGNING FIELD-SYMBOL(<ls_out>) WHERE sel = abap_true.
    READ TABLE gt_item INTO ls_item WITH TABLE KEY id = <ls_out>-id.     " [v1.0]
    IF sy-subrc = 0 AND ( <ls_out>-status = gc_st_open
                          OR ( <ls_out>-status = gc_st_err AND ls_item-pstat = gc_st_open ) ).
      lv_todo = lv_todo + 1.
    ELSE.
      lv_skip = lv_skip + 1.
    ENDIF.
  ENDLOOP.
  IF lv_todo = 0.
    lv_text = COND #( WHEN lv_skip = 0
                      THEN `Tick the rows to post first (selection column on the left)`
                      ELSE `None of the ticked rows can be posted (already created, already in plant, or rejected)` ).
    MESSAGE lv_text TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar       = 'Post batches'
      text_question  = |Create { lv_todo } batch(es) in plant { p_wdst }?| &&
                       |{ COND string( WHEN lv_skip > 0 THEN | ({ lv_skip } ticked row(s) skipped)| ) }|
      text_button_1  = 'Post'
      text_button_2  = 'Cancel'
      default_button = '1'
    IMPORTING
      answer         = lv_answer.
  IF lv_answer <> '1'.
    RETURN.
  ENDIF.

  LOOP AT gt_out ASSIGNING <ls_out> WHERE sel = abap_true.
    READ TABLE gt_item INTO ls_item WITH TABLE KEY id = <ls_out>-id.     " [v1.0]
    IF sy-subrc = 0 AND ( <ls_out>-status = gc_st_open
                          OR ( <ls_out>-status = gc_st_err AND ls_item-pstat = gc_st_open ) ).
      PERFORM f_copy_batch USING ls_item CHANGING <ls_out>.
      IF ls_item-note IS NOT INITIAL.
        <ls_out>-message = |{ <ls_out>-message } ({ ls_item-note })|.
      ENDIF.
      PERFORM f_set_color CHANGING <ls_out>.
      IF <ls_out>-status = gc_st_err.
        lv_err = lv_err + 1.
      ELSE.
        lv_ok = lv_ok + 1.
      ENDIF.
    ENDIF.
    CLEAR <ls_out>-sel.
  ENDLOOP.

  lv_text = |{ lv_ok } batch(es) posted, { lv_err } error(s)|.
  lv_disp = COND #( WHEN lv_err > 0 THEN 'W' ELSE 'S' ).
  MESSAGE lv_text TYPE 'S' DISPLAY LIKE lv_disp.
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
                              WHEN gc_st_ok    THEN 'C510'
                              WHEN gc_st_err   THEN 'C610'
                              WHEN gc_st_test  THEN 'C310'
                              WHEN gc_st_exist THEN 'C410'      " blue [v0.8]
                              ELSE space ).
* grouping of the ALV: ready first (online), then simulated, created,
* errors                                                       [v0.5]
  cs_out-stattx   = SWITCH #( cs_out-status
                              WHEN gc_st_ok    THEN 'Created'
                              WHEN gc_st_err   THEN 'Error'
                              WHEN gc_st_test  THEN 'Simulated'
                              WHEN gc_st_exist THEN 'Already in plant'
                              ELSE 'Ready' ).
  cs_out-sort_key = SWITCH #( cs_out-status
                              WHEN gc_st_test  THEN '2'
                              WHEN gc_st_ok    THEN '3'
                              WHEN gc_st_exist THEN '4'
                              WHEN gc_st_err   THEN '5'
                              ELSE '1' ).
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_COPY_BATCH
*&      Source batch data -> new batch in the target plant, enriched
*&      with the valuation type of the file when the material is split-
*&      valuated in the target plant, without one otherwise.    [v1.0]
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
    IF is_item-split = abap_false.                              " [v1.0]
      cs_out-status  = gc_st_exist.
      cs_out-message = |Batch already exists in plant { p_wdst }|.
    ELSEIF lv_tbwtar IS NOT INITIAL AND lv_tbwtar <> is_item-bwtar.
      cs_out-status  = gc_st_err.
      cs_out-message = |Batch exists in plant { p_wdst } with valuation type { lv_tbwtar }, | &&
                       |file gives { is_item-bwtar }|.
    ELSEIF lv_tbwtar IS INITIAL.
      cs_out-status  = gc_st_err.
      cs_out-message = |Batch exists in plant { p_wdst } without valuation type, | &&
                       |file gives { is_item-bwtar } - not changed|.
    ELSE.
      cs_out-status  = gc_st_exist.                             " [v0.8]
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

* --- valuation type: the file's one (split-valuated), else none [v1.0]
  ls_att-val_type = COND #( WHEN is_item-split = abap_true THEN is_item-bwtar ).
  DATA(lv_vt_txt) = COND string( WHEN is_item-split = abap_true
                                 THEN |with valuation type { is_item-bwtar }|
                                 ELSE `without valuation type (not split-valuated)` ).

  IF gv_sim = abap_true.
    cs_out-status  = gc_st_test.
    cs_out-message = |Simulation: batch would be created in plant { p_wdst } { lv_vt_txt }|.
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
    cs_out-message = |Batch created in plant { p_wdst } { lv_vt_txt }|.
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
  ls_fcat-no_zero = abap_true.                                 " 0 = not in the file [v1.0]
  MODIFY lt_fcat FROM ls_fcat INDEX lines( lt_fcat ).
  add_col 'MATNR'   'Material'.
  add_col 'CHARG'   'Batch'.
  add_col 'BWTAR'   'Val.Type'.
  add_col 'SPLIT'   'Split val.'.                              " [v1.0]
  ls_fcat-checkbox = abap_true.
  MODIFY lt_fcat FROM ls_fcat INDEX lines( lt_fcat ).
  add_col 'MESSAGE' 'Message'.
* technical sort key, not displayed                            [v0.5]
  add_col 'SORT_KEY' 'Sort'.
  ls_fcat-no_out = abap_true.
  MODIFY lt_fcat FROM ls_fcat INDEX lines( lt_fcat ).
  add_col 'ID' 'Item'.                                         " [v1.0]
  ls_fcat-no_out = abap_true.
  MODIFY lt_fcat FROM ls_fcat INDEX lines( lt_fcat ).
  lt_sort = VALUE #( ( spos = 1 fieldname = 'SORT_KEY' up = abap_true )
                     ( spos = 2 fieldname = 'STATTX'   up = abap_true group = 'UL' )
                     ( spos = 3 fieldname = 'MATNR'    up = abap_true )
                     ( spos = 4 fieldname = 'CHARG'    up = abap_true ) ).

  IF gv_sim = abap_true.
    MESSAGE 'SIMULATION - no batch created' TYPE 'S'.
  ENDIF.
  ls_lay-colwidth_optimize = abap_true.
  ls_lay-info_fieldname    = 'ROWCOLOR'.                       " [v0.2]
* online: selection column to tick the rows to post            [v0.8]
  IF p_onl = abap_true.
    ls_lay-box_fieldname = 'SEL'.
  ENDIF.
  DATA(lv_title) = CONV lvc_title( COND #( WHEN p_onl = abap_true
                     THEN |Batches of plant { p_wsrc } - tick them and press Post to create them in plant { p_wdst }|
                     WHEN gv_sim = abap_true
                     THEN |Simulation - batches { p_wsrc } -> { p_wdst }|
                     ELSE |Batches created { p_wsrc } -> { p_wdst }| ) ).
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING i_callback_program       = sy-repid
              i_callback_pf_status_set = COND slis_formname( WHEN p_onl = abap_true
                                                             THEN 'F_SET_STATUS' )
              i_callback_user_command  = 'F_USER_COMMAND'
              i_grid_title            = lv_title
              is_layout               = ls_lay
              it_fieldcat             = lt_fcat
              it_sort                 = lt_sort
    TABLES    t_outtab                = gt_out
    EXCEPTIONS program_error = 1 OTHERS = 2.
ENDFORM.
