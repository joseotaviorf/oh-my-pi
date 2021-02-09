SELECT
    id AS sk_mitula_campaign,
    campaign_name,
    account_name,
    NOW() AS ts_load
FROM 
    datalake_mitula_clean.mitula_report
WHERE 
    AND DATE(dt) = DATE('{year}-{month}-{day}')