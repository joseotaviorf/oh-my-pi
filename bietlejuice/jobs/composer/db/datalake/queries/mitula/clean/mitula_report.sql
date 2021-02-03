SELECT
    INT(id),
    name AS campaign_name,
    account_name, 
    INT(clicks),
    FLOAT(desktop_cost),
    FLOAT(mobile_cost), 
    FLOAT(total_cost),
    INT(acc),
    DATE(curr_date),
    dt
FROM
    datalake_lifull_campaigns_raw.campaigns_report
WHERE
    group_name = 'mitula'
    AND DATE(dt) = DATE('{year}-{month}-{day}')