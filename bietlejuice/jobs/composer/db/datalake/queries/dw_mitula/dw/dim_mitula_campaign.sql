SELECT
    BIGINT(string(id_campaign) || DATE_FORMAT(DATE(dt_loaded), 'yyyyMMdd')) AS sk_mitula_campaign,
    campaign_name,
    account_name,
    {year} AS year,
    {month} AS month,
    {day} AS day,
    NOW() AS ts_load
FROM 
    datalake_lifull_campaigns_clean.mitula_campaigns
WHERE 
    DATE(dt_attribution) = DATE('{year}-{month}-{day}')
