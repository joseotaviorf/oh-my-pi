SELECT
    id AS sk_mitula_campaign,
    campaign_name,
    account_name,
    {year} as year,
    {month} as month,
    {day} as day,
    NOW() AS ts_load
FROM 
    datalake_mitula_clean.mitula_report
WHERE 
    DATE(dt) = DATE('{year}-{month}-{day}')
