SELECT
    id AS id_inspection_opted_out,
    termination_id AS id_termination,
    exit_inspection_opt_out AS is_exit_inspection_opt_out,
    reason,
    reason_details,
    date_opt_out AS dt_opt_out,
    year,
    month,
    day
FROM
    datalake_terminator_raw.inspection_opted_out
