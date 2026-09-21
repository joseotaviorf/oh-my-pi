-- Query for cleaning customer_size_ranges
SELECT
    NULLIF(idpais, '') AS id_country,
    NULLIF(fuente, '') AS source,
    NULLIF(moneda, '') AS currency,
    NULLIF(jumbo, '') AS jumbo,
    NULLIF(big, '') AS big,
    NULLIF(medium, '') AS medium,
    NULLIF(small, '') AS small,
    CASE
        WHEN length(NULLIF(periodo_desde, '')) = 6
        THEN to_date(NULLIF(periodo_desde, ''), 'yyyyMM')
        ELSE to_date(NULLIF(periodo_desde, ''))
    END AS dt_period_start,
    CASE
        WHEN length(NULLIF(periodo_hasta, '')) = 6
        THEN to_date(NULLIF(periodo_hasta, ''), 'yyyyMM')
        ELSE to_date(NULLIF(periodo_hasta, ''))
    END AS dt_period_end,
    ts_load
FROM
    datalake_gsheets_raw.customer_size_ranges
