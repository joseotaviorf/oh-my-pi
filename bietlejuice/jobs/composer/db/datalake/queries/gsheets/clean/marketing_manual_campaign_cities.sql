SELECT
    NULLIF(campaign_name, '') AS campaign_name,
    NULLIF(account_name, '') AS account_name,
    NULLIF(city_group, '') AS city_group,
    NULLIF(side, '') AS side
FROM
    datalake_gsheets_raw.marketing_manual_campaign_cities