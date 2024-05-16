SELECT
    acc AS id_account,
    id AS id_campaign,
    name AS campaign_name,
    account_name,
    CASE
        WHEN account_name LIKE '%mx%' THEN 'MX'
        WHEN account_name LIKE '%br%' THEN  'BR'
        ELSE 'Undefined'
    END AS country_code,
    INT(clicks),
    FLOAT(desktop_cost),
    FLOAT(mobile_cost),
    FLOAT(total_cost),
    DATE(curr_date) AS dt_loaded,
    DATE(dt) AS dt_attribution
FROM
    datalake_lifull_campaigns_raw.campaigns_overview_report
WHERE
    group_name = 'trovit'
    AND DATE(dt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
