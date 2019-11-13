select distinct
    id as sk_campaign,
    id as id_campaign,
    name as campaign_name,
    cost_type,
    type,
    locale_country,
    locale_language,
    current_timestamp as ts_load
from datalake_clean.marketing_linkedin_campaigns;