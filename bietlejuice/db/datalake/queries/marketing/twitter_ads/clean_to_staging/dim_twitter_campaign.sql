select distinct
    id as sk_campaign,
    id as id_campaign,
    name as campaign_name,
    id_account,
    account_name,
    current_timestamp as ts_load
from datalake_clean.marketing_twitter_campaigns;