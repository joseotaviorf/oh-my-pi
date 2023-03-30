SELECT
    DATE(reference_date) AS dt_reference_date,
    owner,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.reference_sla_days