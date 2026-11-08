*&---------------------------------------------------------------------*
*& Report  ZPTP_SPLIT_VAL_MIG_UTILITY
*&---------------------------------------------------------------------*
*& Project : HBM - Split Valuation migration
*& Scope   : Preparation of the Valuation Type Input File
*& Version : v0.5
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
*&   - Valuation type (v0.5), always from plant 2:
*&       - material not split-valuated in plant 2 (MBEW header row,
*&         BWTAR blank, has no valuation category BWTTY - same test as
*&         ZPTP_SPLIT_VAL_MIG): BWTAR blank, the line is written with
*&         its plant-level quantity (one line per batch, storage
*&         locations summed);
*&       - split-valuated, batch-managed: BWTAR of the batch master in
*&         plant 2 (MCHA-BWTAR). Batch missing in plant 2, batch without
*&         valuation type, or valuation type without MBEW segment in
*&         plant 2 -> not in file;
*&       - split-valuated, not batch-managed: first valuation type in
*&         ascending order whose standard price (MBEW-STPRS) is not
*&         zero. None -> not in file.
*&   - ALV (v0.5): rows of materials not managed by batch are blue,
*&     rows of materials not split-valuated in plant 2 are orange
*&     (orange wins when both apply); columns "Not batch-managed" and
*&     "Not split-valuated" carry the same information.
*&   - Zero-quantity lines are left out unless P_ZERO is set.
*&   - Test mode (P_TEST, default on): only the ALV is produced, no
*&     file is built and no save dialog is opened.
*&   - Stock extracted (v0.2), same choice as the transfer mode of
*&     ZPTP_SPLIT_VAL_MIG, so that the file passes its quantity check:
*&       P_XUNR unrestricted (MCHB-CLABS / MARD-LABST, default),
*&       P_XBLK blocked (CSPEM / SPEME),
*&       P_XQI  quality inspection without inspection lot (CINSM / INSME
*&              minus the open, stock-relevant inspection lots, QALS-
*&              LMENGEZUB, per material / batch / storage location).
*&     QUANTITY is then that stock instead of the unrestricted stock.
*&   - P_XQIL (v0.3): quality inspection stock held by the open,
*&     stock-relevant inspection lots only (the part P_XQI leaves out),
*&     per material / batch / storage location, capped at the QI stock.
*&     For analysis and reconciliation: ZPTP_SPLIT_VAL_MIG does not
*&     transfer QI stock held by inspection lots.
*&   - Execution mode (v0.4):
*&       P_ONL online (default): unchanged, the file is downloaded to
*&             the PC through a save dialog.
*&       P_BGD background: F8 schedules the report as a background job
*&             started immediately, with the same selection (job
*&             ZPTP_SPLIT_VAL_UTIL, SM37). The job writes the file to the
*&             application-server directory P_DIR (default /tmp,
*&             F4 = directory browser of the server) as
*&             ZPTP_SPLIT_VAL_<plant1>_<plant2>_<stock>_<date>_<time>.csv
*&             (UTF-8) and lists the ALV in its spool. Download the file
*&             with CG3Y, or read it directly in ZPTP_SPLIT_VAL_MIG with
*&             the application-server option. P_TEST applies: in test
*&             mode the job writes no file.
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

TYPE-POOLS: abap, icon, col.

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
  gc_st_err  TYPE c VALUE 'E',   " left out, see message
* background mode                                              [v0.4]
  gc_ucomm_run TYPE sy-ucomm  VALUE 'RUN',       " click on the mode radio buttons
  gc_jobname   TYPE btcjob    VALUE 'ZPTP_SPLIT_VAL_UTIL'.

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
         stprs TYPE stprs,          " standard price             [v0.5]
       END OF gty_vt,
       gtt_vt TYPE SORTED TABLE OF gty_vt WITH UNIQUE KEY matnr bwtar.

TYPES: BEGIN OF gty_batch,
         matnr TYPE matnr,
         charg TYPE charg_d,
         bwtar TYPE bwtar_d,        " valuation type of the batch [v0.5]
       END OF gty_batch,
       gtt_batch TYPE SORTED TABLE OF gty_batch WITH UNIQUE KEY matnr charg.

TYPES: BEGIN OF gty_stock,
         matnr TYPE matnr,
         charg TYPE charg_d,
         menge TYPE p LENGTH 13 DECIMALS 3,
         qitot TYPE p LENGTH 13 DECIMALS 3,   " QI mode: total QI stock      [v0.2]
         qilot TYPE p LENGTH 13 DECIMALS 3,   " QI mode: part in inspection lots
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
         stktyp TYPE c LENGTH 30,       " stock type the quantity comes from [v0.2]
         qitot  TYPE p LENGTH 13 DECIMALS 3,  " QI mode: total QI stock       [v0.2]
         qilot  TYPE p LENGTH 13 DECIMALS 3,  " QI mode: in inspection lots (stays)
         infile TYPE abap_bool,
         newbat TYPE abap_bool,
         nobat  TYPE abap_bool,          " not batch-managed            [v0.5]
         nosplt TYPE abap_bool,          " not split-valuated in plant 2
         msg    TYPE c LENGTH 100,
         t_color TYPE lvc_t_scol,        " row colour of the ALV
       END OF gty_out,
       gtt_out TYPE STANDARD TABLE OF gty_out WITH DEFAULT KEY.

*&---------------------------------------------------------------------*
*&  Data
*&---------------------------------------------------------------------*
DATA: gt_mat1  TYPE gtt_mat,       " materials of plant 1
      gt_mat2  TYPE gtt_mat,       " materials of plant 2
      gt_vt2   TYPE gtt_vt,        " valuation-type segments of plant 2
      gt_bat2  TYPE gtt_batch,     " batches existing in plant 2
      gt_split2 TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line, " split-valuated in plant 2 [v0.5]
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

* stock extracted, as the transfer mode of ZPTP_SPLIT_VAL_MIG   [v0.2]
SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE gv_tit3.
  PARAMETERS: p_xunr RADIOBUTTON GROUP xfr DEFAULT 'X',          " unrestricted
              p_xblk RADIOBUTTON GROUP xfr,                      " blocked
              p_xqi  RADIOBUTTON GROUP xfr,                      " QI without inspection lot
              p_xqil RADIOBUTTON GROUP xfr.                      " QI in inspection lots [v0.3]
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_tit2.
  PARAMETERS: p_zero TYPE abap_bool AS CHECKBOX,                " include zero-quantity lines
              p_incl TYPE abap_bool AS CHECKBOX,                " ALV: only rows included in the file
              p_test TYPE abap_bool AS CHECKBOX DEFAULT 'X'.    " test: ALV only, no file
SELECTION-SCREEN END OF BLOCK b2.

* execution mode                                               [v0.4]
SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE gv_tit4.
  PARAMETERS: p_onl RADIOBUTTON GROUP run DEFAULT 'X' USER-COMMAND run, " online: save dialog
              p_bgd RADIOBUTTON GROUP run.                              " background job: server file
  PARAMETERS: p_dir TYPE string LOWER CASE DEFAULT '/tmp' MODIF ID bgd. " server directory
SELECTION-SCREEN END OF BLOCK b4.

*&---------------------------------------------------------------------*
*&  Events
*&---------------------------------------------------------------------*
INITIALIZATION.
* texts set here so that no text-element maintenance is needed
  gv_tit1 = 'Selection'.
  gv_tit2 = 'Options'.
  gv_tit3 = 'Stock to extract'.
  %_p_xunr_%_app_%-text   = '1 Unrestricted stock'.
  %_p_xblk_%_app_%-text   = '2 Blocked stock'.
  %_p_xqi_%_app_%-text    = '3 QI stock without insp. lot'.
  %_p_xqil_%_app_%-text   = '4 QI stock in inspection lot'.
  %_p_werks1_%_app_%-text = 'Plant 1 (stock)'.
  %_p_werks2_%_app_%-text = 'Plant 2 (valuation types)'.
  %_s_matnr_%_app_%-text  = 'Material'.
  %_s_charg_%_app_%-text  = 'Batch'.
  %_p_zero_%_app_%-text   = 'Include zero-quantity lines'.
  %_p_incl_%_app_%-text   = 'Records in file only'.
  %_p_test_%_app_%-text   = 'Test mode (ALV only, no file)'.
  gv_tit4 = 'Execution mode'.                                   " [v0.4]
  %_p_onl_%_app_%-text    = '1 Online (download to PC)'.
  %_p_bgd_%_app_%-text    = '2 Background (server file)'.
  %_p_dir_%_app_%-text    = 'Server directory'.

* the server directory only applies to the background mode    [v0.4]
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-group1 = 'BGD'.
      screen-input = COND #( WHEN p_bgd = abap_true THEN '1' ELSE '0' ).
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

* directory browser of the application server                 [v0.4]
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_dir.
  PERFORM f_f4_dir.

AT SELECTION-SCREEN.
* a click on the mode radio buttons only refreshes the screen  [v0.4]
  CHECK sy-ucomm <> gc_ucomm_run.
  PERFORM f_check_plants.
  PERFORM f_check_mode.

START-OF-SELECTION.
* background mode started from the screen: hand the run over to a
* background job started immediately                          [v0.4]
  IF p_bgd = abap_true AND sy-batch = abap_false.
    PERFORM f_submit_job.
    RETURN.
  ENDIF.

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
    IF p_bgd = abap_true.                                       " [v0.4]
      PERFORM f_write_server_file.
    ELSE.
      PERFORM f_download_file.
    ENDIF.
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
*&      Form  F_CHECK_MODE                                      [v0.4]
*&      A background job has no SAP GUI: the file can only be written
*&      to the application server, which needs a directory.
*&---------------------------------------------------------------------*
FORM f_check_mode.
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'SJOB' OR sy-ucomm = 'PRIN'.
  IF sy-ucomm = 'SJOB' AND p_onl = abap_true AND p_test = abap_false.
    MESSAGE 'A background job cannot download to the PC - choose the Background mode'
            TYPE 'E'.
  ENDIF.
  IF p_bgd = abap_true AND p_test = abap_false AND condense( p_dir ) = ``.
    MESSAGE 'Background mode: enter the application-server directory (AL11)' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_F4_DIR                                          [v0.4]
*&      Browser of the application-server directories, starting from
*&      the directory in P_DIR (/tmp when empty). Each popup lists
*&      the sub-directories of the current directory (kernel calls
*&      C_DIR_READ_*, entry type "directory"; no authorization check,
*&      only names are listed - writing the file checks S_DATASET):
*&        - "Use this directory" puts the current directory in P_DIR,
*&        - ".." goes up one level,
*&        - a sub-directory opens it.
*&      Cancel leaves P_DIR unchanged.
*&---------------------------------------------------------------------*
FORM f_f4_dir.
  CONSTANTS: lc_use TYPE string VALUE '>> Use this directory',
             lc_up  TYPE string VALUE '.. (parent directory)'.
  TYPES: BEGIN OF lty_entry,
           name TYPE eps2filnam,
         END OF lty_entry.
  DATA: lt_dynp   TYPE STANDARD TABLE OF dynpread,
        lt_entry  TYPE STANDARD TABLE OF lty_entry,
        lt_subdir TYPE STANDARD TABLE OF lty_entry,
        lt_ret    TYPE STANDARD TABLE OF ddshretval,
        lv_dir    TYPE string,
        lv_sep    TYPE string,
        lv_dirnam TYPE eps2filnam,                 " kernel directory read
        lv_filenm TYPE eps2filnam VALUE '*',
        lv_type   TYPE c LENGTH 10,
        lv_name   TYPE eps2filnam,
        lv_len    TYPE p LENGTH 8 DECIMALS 0,
        lv_owner  TYPE c LENGTH 8,
        lv_mtime  TYPE p LENGTH 6 DECIMALS 0,
        lv_mode   TYPE c LENGTH 9,
        lv_errno  TYPE c LENGTH 3,
        lv_errmsg TYPE c LENGTH 40,
        lv_pick   TYPE string.

* the field may hold a path typed but not yet sent to the program
  lt_dynp = VALUE #( ( fieldname = 'P_DIR' ) ).
  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING  dyname     = sy-repid
               dynumb     = sy-dynnr
    TABLES     dynpfields = lt_dynp
    EXCEPTIONS OTHERS     = 1.
  IF sy-subrc = 0.
    READ TABLE lt_dynp INTO DATA(ls_dynp) INDEX 1.
    IF sy-subrc = 0.
      lv_dir = condense( CONV string( ls_dynp-fieldvalue ) ).
    ENDIF.
  ENDIF.
  IF lv_dir IS INITIAL.
    lv_dir = `/tmp`.
  ENDIF.
  lv_sep = COND #( WHEN lv_dir CA '/' THEN `/` WHEN lv_dir CA '\' THEN `\` ELSE `/` ).

  DO.
*   current directory without its trailing separator (except the root)
    WHILE strlen( lv_dir ) > 1 AND
          substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) = lv_sep AND
          NOT ( strlen( lv_dir ) = 3 AND lv_dir+1(1) = ':' ).     " Windows drive root C:\
      lv_dir = substring( val = lv_dir len = strlen( lv_dir ) - 1 ).
    ENDWHILE.

    lv_dirnam = lv_dir.
    IF CONV string( lv_dirnam ) <> lv_dir.
      MESSAGE 'Path too long for the browser - type it in the field' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

*   sub-directories of the current directory (kernel directory read,
*   as in EPS2_GET_DIRECTORY_LISTING, which lists files only)
    CLEAR lt_subdir.
    CALL 'C_DIR_READ_FINISH'                         " close a previous read
      ID 'ERRNO'  FIELD lv_errno
      ID 'ERRMSG' FIELD lv_errmsg.
    CALL 'C_DIR_READ_START'
      ID 'DIR'    FIELD lv_dirnam
      ID 'FILE'   FIELD lv_filenm
      ID 'ERRNO'  FIELD lv_errno
      ID 'ERRMSG' FIELD lv_errmsg.
    IF sy-subrc <> 0.
      MESSAGE |Directory { lv_dir } cannot be read ({ condense( lv_errmsg ) }) - check it in AL11|
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    DO.
      CLEAR: lv_type, lv_name.
      CALL 'C_DIR_READ_NEXT'
        ID 'TYPE'   FIELD lv_type
        ID 'NAME'   FIELD lv_name
        ID 'LEN'    FIELD lv_len
        ID 'OWNER'  FIELD lv_owner
        ID 'MTIME'  FIELD lv_mtime
        ID 'MODE'   FIELD lv_mode
        ID 'ERRNO'  FIELD lv_errno
        ID 'ERRMSG' FIELD lv_errmsg.
      CASE sy-subrc.
        WHEN 0.
        WHEN 1.
          EXIT.                                      " end of the directory
        WHEN 5.
          CONTINUE.                                  " entry not readable: skip it
        WHEN OTHERS.
          EXIT.                                      " read error: list what was read
      ENDCASE.
      CHECK lv_type(1) CA 'dD' AND lv_name <> '.' AND lv_name <> '..'.
      APPEND VALUE #( name = lv_name ) TO lt_subdir.
    ENDDO.
    CALL 'C_DIR_READ_FINISH'
      ID 'ERRNO'  FIELD lv_errno
      ID 'ERRMSG' FIELD lv_errmsg.

*   popup: use this directory, parent, then the sub-directories
    CLEAR lt_entry.
    APPEND VALUE #( name = |{ lc_use }: { lv_dir }| ) TO lt_entry.
    IF lv_dir <> lv_sep AND NOT ( strlen( lv_dir ) <= 3 AND lv_dir CS ':' ).
      APPEND VALUE #( name = lc_up ) TO lt_entry.
    ENDIF.
    SORT lt_subdir BY name.              " the action lines stay on top
    APPEND LINES OF lt_subdir TO lt_entry.

    CLEAR lt_ret.
    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING  retfield        = 'NAME'
                 window_title    = CONV char40( |Directories in { lv_dir }| )
                 value_org       = 'S'
      TABLES     value_tab       = lt_entry
                 return_tab      = lt_ret
      EXCEPTIONS parameter_error = 1
                 no_values_found = 2
                 OTHERS          = 3.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE lt_ret INTO DATA(ls_ret) INDEX 1.
    IF sy-subrc <> 0 OR ls_ret-fieldval IS INITIAL.
      RETURN.                                          " cancelled
    ENDIF.
    lv_pick = ls_ret-fieldval.

    IF lv_pick CP |{ lc_use }*|.
*     chosen: back to the field with a trailing separator
      p_dir = COND #( WHEN substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) = lv_sep
                      THEN lv_dir
                      ELSE lv_dir && lv_sep ).
      RETURN.
    ELSEIF lv_pick = lc_up.
      FIND ALL OCCURRENCES OF lv_sep IN lv_dir MATCH OFFSET DATA(lv_off).
      lv_dir = COND #( WHEN lv_off = 0 THEN lv_sep                         " Unix root
                       WHEN lv_off = 2 AND lv_dir+1(1) = ':'
                       THEN substring( val = lv_dir len = 3 )               " Windows C:\
                       ELSE substring( val = lv_dir len = lv_off ) ).
    ELSE.
      lv_dir = COND #( WHEN substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) = lv_sep
                       THEN lv_dir && lv_pick
                       ELSE lv_dir && lv_sep && lv_pick ).
    ENDIF.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_SUBMIT_JOB                                      [v0.4]
*&      Background mode started in dialog: the report submits itself
*&      with the same selection as a background job (JOB_OPEN, SUBMIT
*&      VIA JOB, JOB_CLOSE with immediate start). The job writes the file
*&      to the server; its ALV goes to the spool (SM37 -> Spool).
*&      Releasing a job needs the authorization S_BTCH_JOB (RELE);
*&      without it the job stays scheduled and must be released in SM37.
*&---------------------------------------------------------------------*
FORM f_submit_job.
  DATA: lv_jobname  TYPE btcjob VALUE gc_jobname,
        lv_jobcount TYPE btcjobcnt,
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

  SUBMIT zptp_split_val_mig_utility
    WITH p_werks1 = p_werks1
    WITH p_werks2 = p_werks2
    WITH s_matnr  IN s_matnr
    WITH s_charg  IN s_charg
    WITH p_xunr   = p_xunr
    WITH p_xblk   = p_xblk
    WITH p_xqi    = p_xqi
    WITH p_xqil   = p_xqil
    WITH p_zero   = p_zero
    WITH p_incl   = p_incl
    WITH p_test   = p_test
    WITH p_onl    = space
    WITH p_bgd    = abap_true
    WITH p_dir    = p_dir
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
  ELSEIF p_test = abap_true.
    MESSAGE |Job { lv_jobname } ({ lv_jobcount }) started in test mode (no file) - | &&
            |the ALV is in its spool (SM37)| TYPE 'S'.
  ELSE.
    MESSAGE |Job { lv_jobname } ({ lv_jobcount }) started - the file is written to { p_dir }, | &&
            |its name is in the job log (SM37)| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_MATERIALS
*&      Plant 1: base unit and batch-management flag. Plant 2:
*&      extension of the material, split valuation (header row), the
*&      valuation-type segments with their standard price, and the
*&      batch master with its valuation type.
*&---------------------------------------------------------------------*
FORM f_read_materials.
  CLEAR: gt_mat1, gt_mat2, gt_vt2, gt_split2.

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

* split-valuated in plant 2: the header row (BWTAR blank) carries a
* valuation category, as tested by ZPTP_SPLIT_VAL_MIG          [v0.5]
  SELECT matnr FROM mbew
    WHERE bwkey = @p_werks2
      AND matnr IN @s_matnr
      AND bwtar = @space
      AND bwtty <> @space
    INTO TABLE @gt_split2.

* the segment without valuation type (BWTAR blank) is not a split
* valuation segment
  SELECT matnr, bwtar, stprs FROM mbew
    WHERE bwkey = @p_werks2
      AND matnr IN @s_matnr
      AND bwtar <> @space
    INTO CORRESPONDING FIELDS OF TABLE @gt_vt2.

* batch master of plant 2: valuation type of the batch, and the batches
* still missing there (flagged in the ALV)                     [v0.5]
  CLEAR gt_bat2.
  SELECT matnr, charg, bwtar FROM mcha
    WHERE werks = @p_werks2
      AND matnr IN @s_matnr
      AND charg IN @s_charg
    INTO CORRESPONDING FIELDS OF TABLE @gt_bat2.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_READ_STOCK
*&      Stock of plant 1 selected on the screen (unrestricted, blocked,
*&      or QI without inspection lot), summed over storage locations.
*&---------------------------------------------------------------------*
FORM f_read_stock.

  TYPES: BEGIN OF lty_lot,
           matnr TYPE matnr,
           charg TYPE charg_d,
           lgort TYPE lgort_d,
           menge TYPE p LENGTH 13 DECIMALS 3,
         END OF lty_lot.
  DATA: lt_lot TYPE SORTED TABLE OF lty_lot WITH UNIQUE KEY matnr charg lgort,
        ls_lot TYPE lty_lot,
        ls_stk TYPE gty_stock.

  CLEAR gt_stock.

* QI modes: QI stock held by open, stock-relevant inspection lots
  IF p_xqi = abap_true OR p_xqil = abap_true.                  " [v0.3]
    SELECT matnr, charg, lagortchrg, lmengezub
      FROM qals
      WHERE werk      =  @p_werks1
        AND matnr     IN @s_matnr
        AND insmk     =  @abap_true
        AND lmengezub >  0
      INTO TABLE @DATA(lt_qals).
    LOOP AT lt_qals INTO DATA(ls_qals).
      ls_lot = VALUE #( matnr = ls_qals-matnr charg = ls_qals-charg
                        lgort = ls_qals-lagortchrg menge = ls_qals-lmengezub ).
      COLLECT ls_lot INTO lt_lot.
    ENDLOOP.
  ENDIF.

* --- batch-managed materials: MCHB per storage location ------------
  SELECT matnr, charg, lgort, clabs, cspem, cinsm
    FROM mchb
    WHERE werks = @p_werks1
      AND matnr IN @s_matnr
      AND charg IN @s_charg
    INTO TABLE @DATA(lt_mchb).

  LOOP AT lt_mchb INTO DATA(ls_mchb).
    CLEAR ls_stk.
    ls_stk-matnr = ls_mchb-matnr.
    ls_stk-charg = ls_mchb-charg.
    IF p_xblk = abap_true.
      ls_stk-menge = ls_mchb-cspem.
    ELSEIF p_xqi = abap_true OR p_xqil = abap_true.             " [v0.3]
      ls_stk-menge = ls_mchb-cinsm.
      READ TABLE lt_lot INTO ls_lot
           WITH TABLE KEY matnr = ls_mchb-matnr charg = ls_mchb-charg lgort = ls_mchb-lgort.
      IF sy-subrc = 0.
        ls_stk-menge = ls_stk-menge - ls_lot-menge.
      ENDIF.
      IF ls_stk-menge < 0.
        ls_stk-menge = 0.
      ENDIF.
*     split of the QI stock: without lot (extracted) / in inspection lots
      ls_stk-qitot = ls_mchb-cinsm.
      ls_stk-qilot = ls_mchb-cinsm - ls_stk-menge.
*     mode 4: the part in inspection lots is extracted     [v0.3]
      IF p_xqil = abap_true.
        ls_stk-menge = ls_stk-qilot.
      ENDIF.
    ELSE.
      ls_stk-menge = ls_mchb-clabs.
    ENDIF.
*   modes 2 / 3 / 4: a batch holding none of that stock type is not
*   listed (QI modes: listed as soon as it holds QI stock)
    IF p_xunr = abap_false AND ls_stk-menge = 0 AND ls_stk-qitot = 0.
      CONTINUE.
    ENDIF.
    COLLECT ls_stk INTO gt_stock.
  ENDLOOP.

* non-batch-managed materials carry a blank batch: they can only match
* a batch selection that admits a blank
  IF space IN s_charg.
    SELECT matnr, lgort, labst, speme, insme
      FROM mard
      WHERE werks = @p_werks1
        AND matnr IN @s_matnr
      INTO TABLE @DATA(lt_mard).
    LOOP AT lt_mard INTO DATA(ls_mard).
      READ TABLE gt_mat1 INTO DATA(ls_mat) WITH TABLE KEY matnr = ls_mard-matnr.
      CHECK sy-subrc = 0 AND ls_mat-batchmgd = abap_false.
      CLEAR ls_stk.
      ls_stk-matnr = ls_mard-matnr.
      IF p_xblk = abap_true.
        ls_stk-menge = ls_mard-speme.
      ELSEIF p_xqi = abap_true OR p_xqil = abap_true.           " [v0.3]
        ls_stk-menge = ls_mard-insme.
        READ TABLE lt_lot INTO ls_lot
             WITH TABLE KEY matnr = ls_mard-matnr charg = space lgort = ls_mard-lgort.
        IF sy-subrc = 0.
          ls_stk-menge = ls_stk-menge - ls_lot-menge.
        ENDIF.
        IF ls_stk-menge < 0.
          ls_stk-menge = 0.
        ENDIF.
        ls_stk-qitot = ls_mard-insme.
        ls_stk-qilot = ls_mard-insme - ls_stk-menge.
        IF p_xqil = abap_true.                                  " [v0.3]
          ls_stk-menge = ls_stk-qilot.
        ENDIF.
      ELSE.
        ls_stk-menge = ls_mard-labst.
      ENDIF.
      IF p_xunr = abap_false AND ls_stk-menge = 0 AND ls_stk-qitot = 0.
        CONTINUE.
      ENDIF.
      COLLECT ls_stk INTO gt_stock.
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
    DATA(ls_out) = VALUE gty_out( matnr  = ls_stk-matnr
                                  charg  = ls_stk-charg
                                  menge  = ls_stk-menge
                                  qitot  = ls_stk-qitot
                                  qilot  = ls_stk-qilot
                                  stktyp = COND #( WHEN p_xblk = abap_true
                                                   THEN 'Blocked'
                                                   WHEN p_xqi  = abap_true
                                                   THEN 'QI without insp. lot'
                                                   WHEN p_xqil = abap_true
                                                   THEN 'QI in insp. lot'
                                                   ELSE 'Unrestricted' ) ).
    READ TABLE gt_mat1 INTO DATA(ls_mat) WITH TABLE KEY matnr = ls_stk-matnr.
    IF sy-subrc = 0.
      ls_out-meins = ls_mat-meins.
      ls_out-nobat = xsdbool( ls_mat-batchmgd = abap_false ).    " [v0.5]
    ELSE.
      ls_out-nobat = xsdbool( ls_stk-charg IS INITIAL ).
    ENDIF.
*   split valuation in plant 2 (a material missing in plant 2 is
*   reported by F_FIND_BWTAR, not flagged here)                [v0.5]
    READ TABLE gt_mat2 TRANSPORTING NO FIELDS WITH TABLE KEY matnr = ls_stk-matnr.
    IF sy-subrc = 0.
      READ TABLE gt_split2 TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_stk-matnr.
      ls_out-nosplt = xsdbool( sy-subrc <> 0 ).
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

    PERFORM f_find_bwtar USING    ls_out-matnr ls_out-charg ls_out-nobat ls_out-nosplt
                         CHANGING ls_out-bwtar ls_out-msg.

    IF ls_out-msg IS NOT INITIAL.
      ls_out-status = gc_st_err.
    ELSEIF ls_out-menge = 0 AND p_zero = abap_false.
      ls_out-status = gc_st_zero.
      ls_out-msg    = COND #( WHEN p_xqil = abap_true AND ls_out-qitot > 0
                              THEN 'No QI stock in inspection lots, not included'
                              WHEN p_xqi = abap_true AND ls_out-qilot > 0
                              THEN 'All QI stock is in inspection lots, not included'
                              ELSE 'Zero quantity, not included' ).
    ELSE.
      ls_out-status = gc_st_ok.
      ls_out-infile = abap_true.
      IF ls_out-nosplt = abap_true.                              " [v0.5]
        ls_out-msg = |Not split-valuated in plant { p_werks2 }: no valuation type|.
      ENDIF.
    ENDIF.

    ls_out-icon = SWITCH #( ls_out-status
                    WHEN gc_st_ok   THEN icon_led_green
                    WHEN gc_st_zero THEN icon_led_yellow
                    ELSE                 icon_led_red ).

*   row colour: orange = not split-valuated, blue = not batch-managed
    IF ls_out-nosplt = abap_true.                                " [v0.5]
      ls_out-t_color = VALUE #( ( color-col = col_group    color-int = 0 color-inv = 0 ) ).
    ELSEIF ls_out-nobat = abap_true.
      ls_out-t_color = VALUE #( ( color-col = col_key      color-int = 0 color-inv = 0 ) ).
    ENDIF.
    APPEND ls_out TO gt_out.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  F_FIND_BWTAR                                      [v0.5]
*&      Valuation type of plant 2 for a stock line. A non-empty CV_MSG
*&      means the line cannot be written.
*&        - not split-valuated in plant 2: no valuation type;
*&        - batch-managed: valuation type of the batch master in plant 2
*&          (MCHA-BWTAR), which must have an MBEW segment there;
*&        - not batch-managed: first valuation type in ascending order
*&          whose standard price is not zero.
*&---------------------------------------------------------------------*
FORM f_find_bwtar USING    iv_matnr  TYPE matnr
                           iv_charg  TYPE charg_d
                           iv_nobat  TYPE abap_bool
                           iv_nosplt TYPE abap_bool
                  CHANGING cv_bwtar  TYPE bwtar_d
                           cv_msg    TYPE gty_out-msg.
  CLEAR: cv_bwtar, cv_msg.

  READ TABLE gt_mat2 TRANSPORTING NO FIELDS WITH TABLE KEY matnr = iv_matnr.
  IF sy-subrc <> 0.
    cv_msg = |Material not extended to plant { p_werks2 }|.
    RETURN.
  ENDIF.

* not split-valuated: the quantity moves without valuation type
  IF iv_nosplt = abap_true.
    RETURN.
  ENDIF.

  IF iv_nobat = abap_false.
*   batch-managed: the batch master of plant 2 gives the valuation type
    READ TABLE gt_bat2 INTO DATA(ls_bat)
         WITH TABLE KEY matnr = iv_matnr charg = iv_charg.
    IF sy-subrc <> 0.
      cv_msg = |Batch does not exist in plant { p_werks2 }|.
      RETURN.
    ENDIF.
    IF ls_bat-bwtar IS INITIAL.
      cv_msg = |Batch has no valuation type in plant { p_werks2 }|.
      RETURN.
    ENDIF.
    READ TABLE gt_vt2 TRANSPORTING NO FIELDS
         WITH TABLE KEY matnr = iv_matnr bwtar = ls_bat-bwtar.
    IF sy-subrc <> 0.
      cv_msg = |Valuation type { ls_bat-bwtar } of the batch has no MBEW segment in plant { p_werks2 }|.
      RETURN.
    ENDIF.
    cv_bwtar = ls_bat-bwtar.
  ELSE.
*   not batch-managed: GT_VT2 is sorted by material and valuation type,
*   the first entry with a standard price is the one taken
    LOOP AT gt_vt2 INTO DATA(ls_vt) WHERE matnr = iv_matnr AND stprs <> 0.
      cv_bwtar = ls_vt-bwtar.
      EXIT.
    ENDLOOP.
    IF cv_bwtar IS INITIAL.
      cv_msg = |No valuation type with a standard price in plant { p_werks2 }|.
    ENDIF.
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

  DATA(lv_stock) = COND string( WHEN p_xblk = abap_true THEN 'BLOCKED'
                                WHEN p_xqi  = abap_true THEN 'QI'
                                WHEN p_xqil = abap_true THEN 'QI_LOT'
                                ELSE 'UNRESTRICTED' ).
  DATA(lv_default) = |ZPTP_SPLIT_VAL_{ p_werks1 }_{ p_werks2 }_{ lv_stock }_{ sy-datum }.csv|.

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
*&      Form  F_WRITE_SERVER_FILE                               [v0.4]
*&      Background mode: writes the file to the application-server
*&      directory P_DIR (UTF-8, no byte-order mark, same content as the
*&      PC download). The time in the name keeps the files of several
*&      runs on the same day apart. A file that cannot be written
*&      cancels the job, so that SM37 shows the failure.
*&---------------------------------------------------------------------*
FORM f_write_server_file.
  DATA: lv_dir  TYPE string,
        lv_file TYPE string,
        lv_msg  TYPE string.

  IF lines( gt_file ) <= 1.
    MESSAGE 'No line qualifies for the file: nothing written' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA(lv_stock) = COND string( WHEN p_xblk = abap_true THEN 'BLOCKED'
                                WHEN p_xqi  = abap_true THEN 'QI'
                                WHEN p_xqil = abap_true THEN 'QI_LOT'
                                ELSE 'UNRESTRICTED' ).

* directory with its trailing separator (/ on Unix, \ on Windows)
  lv_dir = condense( p_dir ).
  IF lv_dir IS INITIAL.                     " job scheduled in SM36 without directory
    MESSAGE 'No application-server directory (P_DIR): no file written' TYPE 'E'.
  ENDIF.
  DATA(lv_sep) = COND string( WHEN lv_dir CA '/' THEN `/`
                              WHEN lv_dir CA '\' THEN `\`
                              ELSE `/` ).
  IF substring( val = lv_dir off = strlen( lv_dir ) - 1 len = 1 ) <> lv_sep.
    lv_dir = lv_dir && lv_sep.
  ENDIF.
  lv_file = |{ lv_dir }ZPTP_SPLIT_VAL_{ p_werks1 }_{ p_werks2 }_{ lv_stock }_| &&
            |{ sy-datum }_{ sy-uzeit }.csv|.

  TRY.
      OPEN DATASET lv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8 MESSAGE lv_msg.
      IF sy-subrc <> 0.
        MESSAGE |File { lv_file } cannot be opened on the server: { lv_msg }| TYPE 'E'.
      ENDIF.
      LOOP AT gt_file INTO DATA(lv_line).
        TRANSFER lv_line TO lv_file.
      ENDLOOP.
      CLOSE DATASET lv_file.
    CATCH cx_sy_file_access_error INTO DATA(lx_file).
      CLOSE DATASET lv_file.
      MESSAGE |File { lv_file } cannot be written: { lx_file->get_text( ) }| TYPE 'E'.
  ENDTRY.

  MESSAGE |{ lines( gt_file ) - 1 } line(s) written to server file { lv_file } | &&
          |- download it with CG3Y| TYPE 'S'.
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
            THEN |Split valuation file (TEST, no file): { p_werks1 } -> { p_werks2 }| &&
                 | - orange: not split-valuated, blue: not batch-managed|
            ELSE |Split valuation file: { p_werks1 } -> { p_werks2 }| &&
                 | - orange: not split-valuated, blue: not batch-managed| ) ).
  lo_alv->get_columns( )->set_optimize( abap_true ).

  TRY.
      DATA(lo_cols) = lo_alv->get_columns( ).
      lo_cols->get_column( 'ICON'   )->set_short_text( 'St.' ).
      lo_cols->get_column( 'STATUS' )->set_visible( abap_false ).
      lo_cols->get_column( 'BWTAR'  )->set_medium_text( 'Val. type (P2)' ).
      lo_cols->get_column( 'MENGE'  )->set_medium_text( 'Quantity' ).
      lo_cols->get_column( 'STKTYP' )->set_short_text( 'Stock' ).
      lo_cols->get_column( 'STKTYP' )->set_medium_text( 'Stock type' ).
      lo_cols->get_column( 'STKTYP' )->set_long_text( 'Stock type of the quantity' ).
*     QI split, shown in QI mode only: Quantity = QI without lot (moved),
*     QI in insp. lots = stays in plant 1, QI total = both
      lo_cols->get_column( 'QITOT'  )->set_short_text( 'QI total' ).
      lo_cols->get_column( 'QITOT'  )->set_medium_text( 'QI stock total' ).
      lo_cols->get_column( 'QITOT'  )->set_long_text( 'Quality inspection stock, total' ).
      lo_cols->get_column( 'QILOT'  )->set_short_text( 'QI in lots' ).
      lo_cols->get_column( 'QILOT'  )->set_medium_text( 'QI in insp. lots' ).
      lo_cols->get_column( 'QILOT'  )->set_long_text( 'QI stock in inspection lots (not moved)' ).
      lo_cols->get_column( 'QITOT'  )->set_visible( xsdbool( p_xqi = abap_true OR p_xqil = abap_true ) ).
      lo_cols->get_column( 'QILOT'  )->set_visible( p_xqi ).
      IF p_xqi = abap_true.
        lo_cols->get_column( 'MENGE' )->set_medium_text( 'QI without lot' ).
        lo_cols->get_column( 'MENGE' )->set_long_text( 'QI stock without insp. lot (in file)' ).
      ELSEIF p_xqil = abap_true.                                  " [v0.3]
*       mode 4: Quantity is the part in lots, QILOT would repeat it
        lo_cols->get_column( 'MENGE' )->set_medium_text( 'QI in insp. lots' ).
        lo_cols->get_column( 'MENGE' )->set_long_text( 'QI stock in inspection lots (in file)' ).
      ENDIF.
      lo_cols->get_column( 'INFILE' )->set_medium_text( 'In file' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'INFILE' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
      lo_cols->get_column( 'NEWBAT' )->set_medium_text( 'New batch in P2' ).
      lo_cols->get_column( 'NEWBAT' )->set_tooltip( 'Batch not yet in plant 2' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'NEWBAT' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
      lo_cols->get_column( 'MSG'    )->set_medium_text( 'Message' ).
*     materials not batch-managed / not split-valuated in plant 2 [v0.5]
      lo_cols->get_column( 'NOBAT'  )->set_short_text( 'No batch' ).
      lo_cols->get_column( 'NOBAT'  )->set_medium_text( 'Not batch-managed' ).
      lo_cols->get_column( 'NOBAT'  )->set_long_text( 'Material not managed by batch' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'NOBAT' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
      lo_cols->get_column( 'NOSPLT' )->set_short_text( 'No split' ).
      lo_cols->get_column( 'NOSPLT' )->set_medium_text( 'Not split-valuated' ).
      lo_cols->get_column( 'NOSPLT' )->set_long_text( 'Material not split-valuated in plant 2' ).
      CAST cl_salv_column_table( lo_cols->get_column( 'NOSPLT' ) )->set_cell_type( if_salv_c_cell_type=>checkbox ).
    CATCH cx_salv_not_found.
  ENDTRY.

* row colours set in F_BUILD_OUTPUT                            [v0.5]
  TRY.
      lo_cols->set_color_column( 'T_COLOR' ).
    CATCH cx_salv_data_error.
  ENDTRY.

  lo_alv->display( ).
ENDFORM.
