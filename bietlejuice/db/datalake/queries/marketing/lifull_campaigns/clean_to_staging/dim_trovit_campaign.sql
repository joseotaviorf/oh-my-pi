select
    cast(id as integer) as sk_trovit_campaign,
    cast(id as integer) as id_campaign,
    name as campaign_name,
    account_name,
    current_timestamp as ts_load
from datalake_clean.marketing_lifull_campaigns
where dt_created  = '{date}' and acc = '{account}'
AND LOWER(group_name) = 'trovit'