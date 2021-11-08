SELECT
    id_sub_campaign AS sk_sub_campaign,
    CAST(DATE_FORMAT(dt_attribution, 'yyyyMMdd') AS INTEGER) AS sk_date,
    clicks,
    impressions,
    click_through_rate AS ctr,
    cost,
    conversions_count,
    conversion_rate,
    NULLIF(cost / clicks, 0) AS cpc,
    year,
    month,
    day,
    CURRENT_TIMESTAMP AS ts_load
FROM
    datalake_rtb_campaigns_clean.rtb_campaigns
WHERE
    year = '{year}'
    AND month = '{month}'
    AND day = '{day}'