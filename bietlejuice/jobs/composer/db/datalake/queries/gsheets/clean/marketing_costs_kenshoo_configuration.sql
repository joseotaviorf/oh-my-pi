SELECT
    mkt_source,
    mkt_medium,
    CAST(rate AS FLOAT) AS cost_factor,
    CAST(date_from AS DATE) AS dt_from,
    CAST(date_until AS DATE) AS dt_until
FROM
    datalake_gsheets_raw.marketing_costs_kenshoo_configuration