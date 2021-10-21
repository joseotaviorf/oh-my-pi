SELECT
    BIGINT(string(id_campaign) || DATE_FORMAT(DATE(dt_loaded), 'yyyyMMdd')) AS sk_trovit_campaign,
    INT(DATE_FORMAT(DATE(dt_loaded), 'yyyyMMdd')) AS sk_date,
    clicks,
    desktop_cost,
    mobile_cost,
    total_cost,
    {year} AS year,
    {month} AS month,
    {day} AS day,
    NOW() AS ts_load
FROM
    datalake_lifull_campaigns_clean.trovit_campaigns
WHERE
    DATE(dt_attribution) = DATE('{year}-{month}-{day}')

