SELECT distinct
    hash as sk_sub_campaign,
    hash as id_campaign,
    name as campaign_name,
    account_hash,
    account_name,
    account_currency,
    current_timestamp as ts_load
FROM datalake_clean.marketing_rtb_sub_campaigns