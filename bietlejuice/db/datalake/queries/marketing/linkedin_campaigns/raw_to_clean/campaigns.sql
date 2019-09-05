select distinct
    account_name,
    campaign_id as id_campaign,
    campaign_name,
    ad_id as id_ad,
    creative_name as ad_name,
    currency,
    REPLACE(REPLACE(daily_budget, '.', ''), ',', '.') as daily_budget,
    REPLACE(REPLACE(account_total_budget, '.', ''), ',', '.') as account_total_budget,
    REPLACE(REPLACE(total_spent, '.', ''), ',', '.') as total_spent,
    REPLACE(REPLACE(impressions, '.', ''), ',', '.') as impressions,
    REPLACE(REPLACE(clicks, '.', ''), ',', '.') as clicks,
    REPLACE(REPLACE(other_clicks, '.', ''), ',', '.') as other_clicks,
    REPLACE(REPLACE(total_engagements, '.', ''), ',', '.') as total_engagements,
    REPLACE(REPLACE(conversions, '.', ''), ',', '.') as conversions,
    REPLACE(REPLACE(cost_per_conversion, '.', ''), ',', '.') as cost_per_conversion,
    REPLACE(REPLACE(cost_per_lead, '.', ''), ',', '.') as cost_per_lead
from datalake_raw.marketing_linkedin_campaigns
WHERE dt='{date}'