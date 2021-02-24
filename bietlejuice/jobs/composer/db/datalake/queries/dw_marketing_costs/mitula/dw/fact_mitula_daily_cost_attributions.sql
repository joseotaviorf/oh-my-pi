SELECT
    BIGINT(string(id) || DATE_FORMAT(DATE(curr_dt), 'yyyyMMdd')) AS sk_mitula_campaign,
    INT(DATE_FORMAT(DATE(curr_dt), 'yyyyMMdd')) AS sk_date,
    clicks,
    desktop_cost,
    mobile_cost,
    total_cost,
    {year} AS year,
    {month} AS month,
    {day} AS day,
    NOW() AS ts_load
FROM 
    datalake_mitula_clean.mitula_report
WHERE 
    DATE(dt) = DATE('{year}-{month}-{day}')