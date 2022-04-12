SELECT
    year_month AS id_year_month,
    region_code_deprecated,
    limit1,
    limit2,
    limit3,
    limit4,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.aux_payments_photos