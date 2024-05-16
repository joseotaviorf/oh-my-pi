SELECT
    INT(YEAR(dt_attribution)*10000 + MONTH(dt_attribution)*100 + DAY(dt_attribution)) AS id_date,
    campaign_name,
    account_name,
    campaign_name AS utm_campaign,
    desktop_cost,
    mobile_cost,
    total_cost,
    clicks
FROM
    datalake_lifull_campaigns_clean.trovit_campaigns
WHERE
    country_code <> 'MX'
    AND dt_attribution BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
