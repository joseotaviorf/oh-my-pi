SELECT
    campaign,
    city_group,
    mkt_source,
    FLOAT(cost) AS cost,
    DATE(cost_date) AS dt_cost
FROM
    datalake_gsheets_raw.historic_national_costs
