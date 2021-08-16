SELECT
    NULLIF(city_name, '') AS city_name,
    NULLIF(network, '') AS network,
    NULLIF(campaign_name, '') AS campaign_name,
    FLOAT(NULLIF(cost, '')) AS cost,
    DATE(NULLIF(dt_cost, '')) AS dt_cost
FROM
    datalake_gsheets_raw.marketing_social_media_costs