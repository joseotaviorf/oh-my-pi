SELECT
    id AS id_inspection_opted_out,
    terminator_id AS id_terminator,
    exit_inspection_opt_out AS is_exit_inspection_opt_out,
    reason,
    reason_details,
    date_opt_out AS dt_opt_out
FROM
    datalake_terminator_test_raw.inspection_opted_out
