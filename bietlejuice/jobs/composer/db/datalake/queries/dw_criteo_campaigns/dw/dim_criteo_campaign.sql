SELECT
    CONCAT(id_campaign, '-', campaign_name) AS sk_criteo_campaign,
    id_campaign,
    advertiser_name,
    campaign_name,
    currency,
    year,
    month,
    day,
    CURRENT_TIMESTAMP AS ts_load
FROM
    datalake_criteo_campaigns_clean.criteo_campaigns
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}