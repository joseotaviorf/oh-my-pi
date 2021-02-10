SELECT
    subcampaign AS sub_campaign,
    COALESCE(subcampaignhash, 'kwKe') AS sub_campaign_hash,
    CAST(cost_attribution_date AS DATE) AS cost_attribution_date,
    impscount AS impressions_count,
    clickscount AS clicks_count,
    ctr,
    campaigncost AS cost,
    conversionscount AS conversions_count,
    cr,
    roas,
    conversionsvalue AS conversions_value,
    account_name,
    account_hash,
    account_status,
    account_currency,
    year,
    month,
    day
FROM
    datalake_marketing_costs_raw.rtb_campaigns
WHERE
    year={year} AND month={month} AND day={day}
