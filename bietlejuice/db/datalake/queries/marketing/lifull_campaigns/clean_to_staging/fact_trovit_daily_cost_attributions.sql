select
    cast(id as integer) as sk_trovit_campaign,
    cast(to_char(cast(curr_date as date), 'YYYYMMDD') as integer) as sk_date,
    cast(clicks as integer) as clicks,
    cast(conversions as integer) as conversions,
    cast(desktop_cost as numeric(10,2)) as desktop_cost,
    cast(mobile_cost as numeric(10,2)) as mobile_cost,
    cast(total_cost as numeric(10,2)) as total_cost,
    current_timestamp as ts_load
from datalake_clean.marketing_lifull_campaigns
WHERE dt_created  = '{date}'
AND LOWER(group_name) = 'trovit'