SELECT DISTINCT
    id_sub_campaign as sk_sub_campaign,
    CAST(DATE_FORMAT(CAST(dt_attribution AS DATE), 'yyyyMMdd') AS INTEGER) AS sk_date,
    id_account,
    sub_campaign_name as campaign_name,
    account_name,
    currency,
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