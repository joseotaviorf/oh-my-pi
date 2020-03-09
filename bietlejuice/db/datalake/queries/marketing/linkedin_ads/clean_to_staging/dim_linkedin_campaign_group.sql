select distinct
    id as sk_campaign_group,
    id as id_campaign_group,
    name as campaign_group_name,
    id_account,
    account_name,
    current_timestamp as ts_load
from
    datalake_clean.marketing_linkedin_campaign_groups
where
    dt_created = '{date}';