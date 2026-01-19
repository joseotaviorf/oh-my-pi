SELECT
    id_visitor,
    id_check_duplicate,
    reason,
    blacklist_date AS dt_blacklist
FROM
    datalake_gsheets_raw.sv_bp_blacklist