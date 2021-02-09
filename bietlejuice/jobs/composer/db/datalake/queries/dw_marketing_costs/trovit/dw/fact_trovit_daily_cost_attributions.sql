SELECT
    id AS sk_trovit_campaign,
    INT(DATE_FORMAT(DATE(curr_dt), 'yyyyMMdd')) AS sk_date,
    clicks,
    desktop_cost,
    mobile_cost,
    total_cost,
    NOW() AS ts_load
FROM
    datalake_trovit_clean.trovit_report
WHERE
    DATE(dt) = DATE('{year}-{month}-{day}')

