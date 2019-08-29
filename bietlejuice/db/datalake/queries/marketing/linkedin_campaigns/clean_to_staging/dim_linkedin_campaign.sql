select distinct
    id_campaign as sk_campaign,
    id_campaign as id_campaign,
    campaign_name,
    id_account,
    current_timestamp as ts_load
from datalake_clean.marketing_linkedin_campaigns;