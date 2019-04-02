select
    cast(id as integer) as sk_trovit_campaign,
    cast(id as integer) as id_campaign,
    name as campaign_name,
    current_timestamp as ts_load
from datalake_clean.marketing_trovit_campaigns
where dt_created  = '{date}' and acc = '{account}'