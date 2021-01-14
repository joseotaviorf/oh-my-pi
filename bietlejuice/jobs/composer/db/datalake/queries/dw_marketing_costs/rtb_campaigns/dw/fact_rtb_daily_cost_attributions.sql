SELECT
    sub_campaign_hash AS sk_sub_campaign,
    CAST(DATE_FORMAT(CAST(cost_attribution_date AS DATE), '%Y%m%d') AS INTEGER) AS sk_date,
    clicks_count as clicks,
    impressions_count as impressions,
    ctr,
    cost,
    conversions_count,
    cr as conversions_rate,
    cpc,
    year,
    month,
    day,
    current_timestamp  AS ts_load
FROM
    datalake_marketing_costs_clean.rtb_campaigns rc
WHERE
    year = '{year}'
    AND month = '{month}'
    AND day = '{day}'
