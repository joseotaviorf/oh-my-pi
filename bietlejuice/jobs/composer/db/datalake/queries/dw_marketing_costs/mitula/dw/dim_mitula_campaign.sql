SELECT
    id AS sk_mitula_campaign,
    campaign_name,
    account_name,
    {year} AS year,
    {month} AS month,
    {day} AS day,
    NOW() AS ts_load
FROM 
    datalake_mitula_clean.mitula_report
WHERE 
    DATE(dt) = DATE('{year}-{month}-{day}')
