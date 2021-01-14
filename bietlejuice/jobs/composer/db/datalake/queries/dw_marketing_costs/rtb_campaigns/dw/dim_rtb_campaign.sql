SELECT distinct
    sub_campaign_hash as sk_sub_campaign,
    sub_campaign as campaign_name,
    account_hash,
    account_name,
    account_currency,
    year,
    month,
    day,
    current_timestamp AS ts_load
FROM
    datalake_marketing_costs_clean.rtb_campaigns
WHERE
    year = '{year}' AND month = '{month}' AND day = '{day}'