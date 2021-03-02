SELECT
    campaign,
    CAST(cost AS FLOAT) AS cost,
    city_group,
    mkt_source,
    CAST(cost_date AS DATE) AS dt_cost
FROM
    datalake_gsheets_raw.marketing_costs_affiliates_historic_national_costs