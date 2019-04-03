select
    cast(id as integer) as sk_trovit_campaign,
    cast(to_char(cast(curr_date as date), 'YYYYMMDD') as integer) as sk_date,
    cast(clicks as integer) as clicks,
    cast(cost as numeric(10,2)) as cost,
    current_timestamp as ts_load
from datalake_clean.marketing_trovit_campaigns
WHERE dt_created  = '{date}' and acc = '{account}'