SELECT
    division,
    status AS hc_status,
    hc AS hc_value,
    month AS dt_reference
FROM
    datalake_gsheets_raw.sale_performance_hc_faturado