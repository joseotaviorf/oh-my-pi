SELECT
    id AS sk_trovit_campaign,
    campaign_name,
    account_name,
    {year} as year,
    {month} as month,
    {day} as day,
    now() AS ts_load
FROM   
    datalake_trovit_clean.trovit_report
WHERE
    DATE(dt) = DATE('{year}-{month}-{day}')
