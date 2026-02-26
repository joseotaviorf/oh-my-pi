SELECT
    period,
    metric,
    division,
    value_format AS target_value_format,
    value AS target_value,
    date AS dt_reference
FROM
    datalake_gsheets_raw.sale_performance_targets