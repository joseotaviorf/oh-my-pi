SELECT
    id AS sk_mitula_campaign,
    DATE_FORMAT(DATE(curr_dt), 'yyyyMMdd') AS sk_date,
    clicks,
    desktop_cost,
    mobile_cost,
    total_cost,
    {year} as year,
    {month} as month,
    {day} as day,
    NOW() AS ts_load
FROM 
    datalake_mitula_clean.mitula_report
WHERE 
    AND DATE(dt) = DATE('{year}-{month}-{day}')