SELECT distinct
    sub_campaign_hash as sk_sub_campaign,
    sub_campaign_hash as id_campaign,
    sub_campaign as campaign_name,
    account_hash,
    account_name,
    account_currency,
    current_timestamp as ts_load
FROM
    datalake_clean.marketing_rtb_stats
WHERE
    dt_created  = '{date}'