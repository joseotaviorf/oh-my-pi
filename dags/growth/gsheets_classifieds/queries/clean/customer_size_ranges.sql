-- Query for cleaning customer_size_ranges
SELECT
    NULLIF(idpais, '') AS id_country,
    NULLIF(fuente, '') AS source,
    NULLIF(moneda, '') AS currency,
    NULLIF(jumbo, '') AS jumbo,
    NULLIF(big, '') AS big,
    NULLIF(medium, '') AS medium,
    NULLIF(small, '') AS small,
    DATE(NULLIF(periodo_desde, '')) AS dt_period_start,
    DATE(NULLIF(periodo_hasta, '')) AS dt_period_end,
    ts_load
FROM
    datalake_gsheets_raw.customer_size_ranges
