with prev as (
  select
    amplitude_id as user_id,
    session_id,
    et as "action",
    try(cast(
      coalesce(
        regexp_extract(trim(e_house_id), '^(\d+)(\.0)?$', 1),
        regexp_extract(trim(e__id__imovel), '^(\d+)(\.0)?$', 1),
        regexp_extract(trim(e_imovel_id), '^(\d+)(\.0)?$', 1),
        regexp_extract(trim(e__imovel_id), '^(\d+)(\.0)?$', 1)
      ) as integer
    )) as house_id,
    cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}[ |T]\d{2}:\d{2}:\d{2}') as timestamp) as action_time
  from datalake_clean.amplitude_events
  where ym between '__START_YM__' and '__END_YM__'
    and et in ('listing_page_viewed', 'visit_intent_clicked')
    and trim(app) = '170698'
    and trim(ip_address) not in ('187.72.188.226', '127.0.0.1', '201.49.126.67')
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
where first_action_time between date '__START_DATE__' and date '__END_DATE__'
  and cardinality(listing_views) >= 5