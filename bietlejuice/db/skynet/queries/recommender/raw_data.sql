with prev as (
  select
    id_amplitude as user_id,
    id_session as session_id,
    event_type as "action",
    try_cast(
      coalesce(
        regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '^(\d+)(\.0)?$', 1),
        regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '^(\d+)(\.0)?$', 1),
        regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '^(\d+)(\.0)?$', 1),
        regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '^(\d+)(\.0)?$', 1)
      ) as integer
    ) as house_id,
    ts_event as action_time
  from {db}.{table_name}
  where cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') between '__START_YM__' and '__END_YM__'
    and event_type in ('listing_page_viewed', 'visit_intent_clicked')
    and id_app = 170698
    and ip_address not in ('187.72.188.226', '127.0.0.1', '201.49.126.67')
),
flg_lag as (
  select
    user_id,
    session_id,
    "action",
    action_time,
    if(house_id < 892700000, 892700000 + house_id, house_id) as house_id,
    lag(house_id) over (partition by user_id, session_id, "action" order by action_time) = house_id as equal_lag
  from prev
  order by user_id,
    session_id,
    action_time
),
dataset as (
  select
    user_id,
    session_id,
    coalesce(
      filter(
        array_agg(if("action" = 'listing_page_viewed', house_id)),
        x -> x is not null
      ),
      array []
    ) as listing_views,
    coalesce(
      filter(
        array_agg(if("action" = 'visit_intent_clicked', house_id)),
        x -> x is not null
      ),
      array []
    ) as visit_intents,
    min(action_time) first_action_time,
    max(action_time) last_action_time
  from flg_lag
  where house_id is not null
    and (equal_lag is null or not equal_lag)
  group by 1, 2
)
select
  *
from dataset
where CAST(first_action_time as date) between date '__START_DATE__' and date '__END_DATE__'
  and cardinality(listing_views) >= 5