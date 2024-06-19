SELECT
    accountHash AS id_account,
    COALESCE(subcampaignHash, 'kwKe') AS id_sub_campaign,
    accountName AS account_name,
    accountStatus AS account_status,
    subcampaign AS sub_campaign_name,
    'BR' AS country_code,
    accountCurrency AS currency,
    impsCount AS impressions,
    clicksCount AS clicks,
    campaignCost AS cost,
    conversionsCount AS conversions_count,
    conversionsValue AS conversions_value,
    ctr AS click_through_rate,
    cr AS conversion_rate,
    roas AS return_on_advertising_spend,
    attributionDate AS dt_attribution
FROM
    datalake_rtb_campaigns_raw.rtb_campaigns
WHERE
    attributionDate BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
