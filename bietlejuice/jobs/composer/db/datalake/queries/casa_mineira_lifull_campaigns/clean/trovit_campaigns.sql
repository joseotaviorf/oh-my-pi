SELECT
    acc AS id_account,
    id AS id_campaign,
    name AS campaign_name,
    account_name,
    INT(clicks),
    FLOAT(desktop_cost),
    FLOAT(mobile_cost), 
    FLOAT(total_cost),
    DATE(curr_date) AS dt_loaded,
    DATE(dt) AS dt_attribution
FROM
    datalake_casa_mineira_lifull_campaigns_raw.campaigns_overview_report
WHERE
    group_name = 'trovit'
    AND DATE(dt) = DATE('{year}-{month}-{day}')