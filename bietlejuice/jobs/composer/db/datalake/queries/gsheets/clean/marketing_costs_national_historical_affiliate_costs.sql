SELECT
    campaign,
    CAST(cost AS FLOAT) AS cost,
    city_group,
    mkt_source,
    CAST(FROM_UNIXTIME(UNIX_TIMESTAMP(cost_date, 'dd/MM/yyyy'), 'yyyyMMdd') AS BIGINT) AS dt_cost
FROM
    datalake_gsheets_raw.marketing_costs_national_historical_affiliate_costs