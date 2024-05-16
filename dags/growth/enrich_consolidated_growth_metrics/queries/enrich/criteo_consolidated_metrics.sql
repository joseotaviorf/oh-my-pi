SELECT
    INT(DATE_FORMAT(dt_attribution,"yyyyMMdd")) AS id_date,
    campaign_name,
    advertiser_name AS account_name,
    country_code,
    campaign_name AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost,
    clicks,
    impressions
FROM
    datalake_criteo_campaigns_clean.criteo_campaigns
WHERE
    dt_attribution BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
