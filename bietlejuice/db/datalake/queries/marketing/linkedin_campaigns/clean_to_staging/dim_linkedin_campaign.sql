select distinct
    id_campaign as sk_campaign,
    id_campaign as id_campaign,
    campaign_name,
    account_name,
    current_timestamp as ts_load
from datalake_clean.marketing_linkedin_campaigns;