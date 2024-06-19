SELECT
    INT(DATE_FORMAT(dt_attribution, 'yyyyMMdd')) AS id_date,
    sub_campaign_name AS campaign_name,
    account_name,
    country_code,
    sub_campaign_name AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost,
    impressions,
    clicks
FROM
    datalake_rtb_campaigns_clean.rtb_campaigns
WHERE
    dt_attribution BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
