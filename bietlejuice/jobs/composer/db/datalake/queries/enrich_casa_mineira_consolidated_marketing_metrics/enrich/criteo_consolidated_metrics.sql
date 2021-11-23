SELECT
    INT(year*10000 + month*100 + day) AS id_date,
    campaign_name,
    advertiser_name AS account_name,
    campaign_name AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost,
    clicks,
    impressions
FROM
    datalake_casa_mineira_criteo_campaigns_clean.criteo_campaigns
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
