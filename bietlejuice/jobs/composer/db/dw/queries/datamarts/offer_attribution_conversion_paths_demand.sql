with listing_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as id_amplitude,
    id_session,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term
  from datalake_amplitude_clean_staging.170698_listing_page_viewed_events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
  where year >= 2019 and platform = 'Web'
  group by 2,3,4,5,6,7,8
),
home_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as id_amplitude,
    id_session,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term
  from datalake_amplitude_clean_staging.170698_home_page_viewed_events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
  where year >= 2019 and platform = 'Web'
  group by 2,3,4,5,6,7,8
),
search_results_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as id_amplitude,
    id_session,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term
  from datalake_amplitude_clean_staging.170698_search_results_page_viewed_events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
  where year >= 2019 and platform = 'Web'
  group by 2,3,4,5,6,7,8
),
schedule_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as id_amplitude,
    id_session,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term
  from datalake_amplitude_clean_staging.170698_schedule_page_viewed_events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
  where year >= 2019 and platform = 'Web'
  group by 2,3,4,5,6,7,8
),
offer_submitted_aux as (
  select
    ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) id_amplitude,
    id_session,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
    get_json_object(event_properties, '$.visit_code') as visit_code,
    get_json_object(event_properties, '$.house_id') as house_id
  from datalake_amplitude_clean.events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_amplitude_raw.`170698_user_merge` amu
    on damcs.id_amplitude = amu.amplitude_id
  where year >= 2020
    and platform = 'Web'
    and id_app = 170698 
    and event_type = 'offer_submitted'
  group by 1,2,3,4,5,6,7,8,9,10
),
offer_submitted_conversions as (
  select distinct
    osa.ts_event,
    osa.id_amplitude,
    osa.id_session,
    osa.utm_source,
    osa.utm_medium,
    osa.utm_campaign,
    osa.utm_content,
    osa.utm_term,
    osa.visit_code,
    dcodr.city_group as city
  from offer_submitted_aux osa
  left join dw_public.fact_house_listings clofhl
    on cast(osa.house_id as integer) = cast(clofhl.sk_house_listing as BIGINT)/1000
  left join dw_public.dim_region dcodr 
    on cast(clofhl.sk_region as integer) = cast(dcodr.sk_region as integer)
  group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
offer_submitted_sessions as (
  select distinct
    min(osc.ts_event) as ts_event,
    osc.id_amplitude,
    osc.id_session,
    osc.utm_source,
    osc.utm_medium,
    osc.utm_campaign,
    osc.utm_content,
    osc.utm_term
  from offer_submitted_conversions osc
  group by 2, 3, 4, 5, 6, 7, 8
),
pre_events as (
    select * from listing_page_viewed
    union all
    select * from home_page_viewed
    union all
    select * from search_results_page_viewed
    union all
    select * from schedule_page_viewed
    union all
    select * from offer_submitted_sessions
),
events_rank as (
  select
    min(ts_event) as ts_event,
    -- Using the colaesced id to get the rank
    id_amplitude,
    id_session
  from pre_events
  group by 2,3
),
events as (
  select
    p.*
  from pre_events p
  inner join events_rank r
    on p.ts_event=r.ts_event
    and p.id_amplitude=r.id_amplitude
    and p.id_session=r.id_session
),
conversion_sessions_unique as (
  -- retrieve conversion sessions, indicating last conversion session
  select
    oss.id_session,
    oss.id_amplitude,
    er.ts_event as ts_session,
    nullif(lag(er.ts_event) over (partition by oss.id_amplitude order by er.ts_event), er.ts_event) as ts_last_session
  from offer_submitted_sessions oss
  join events_rank er on er.id_amplitude = oss.id_amplitude and er.id_session = oss.id_session
  group by 1, 2, 3
),
conversion_events as (
  -- retrieve conversion events together with their session info
  select 
    osc.ts_event,
    osc.id_session,
    osc.id_amplitude,
    osc.visit_code,
    osc.city,
    csu.ts_session,
    csu.ts_last_session,
    rank() over (partition by osc.id_amplitude order by osc.ts_event) as rnk_conversion
  from offer_submitted_conversions osc
  join conversion_sessions_unique csu on csu.id_amplitude = osc.id_amplitude and csu.id_session = osc.id_session  
),
touchpoints as (
  -- aggregate events to attributed sessions (=touchpoints)
  -- determine for each session the start_time and the time of closest conversion event
  -- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
  select
    -- Collect the coalesced id
    evt.id_amplitude,
    evt.id_session,
    evt.utm_source || '/' || evt.utm_medium as utm_source_medium,
    evt.utm_source || '/' || evt.utm_medium || '/' ||
    (case when evt.utm_campaign like '%branded%' and lower(evt.utm_campaign) not like '%non-branded%' then 'true'
        when evt.utm_campaign like '%institucional%' then 'true'
        else 'false' end)
    as utm_source_medium_branded,
    evt.utm_source,
    evt.utm_medium,
    evt.utm_campaign,
    evt.utm_content,
    evt.utm_term,
    evt.ts_event as session_start_time,
    conv.city,
    conv.ts_event as conversion_time,
    conv.rnk_conversion as nst_conversion
  from conversion_events conv
  left join events evt
  	on evt.id_amplitude = conv.id_amplitude
  	and evt.ts_event > coalesce(conv.ts_last_session, date('2000-01-01')) -- join events that happened between last conversion and current conversion
    and evt.ts_event <= conv.ts_session 
  group by 1,2,3,4,5,6,7,8,9,10,11,12,13
  order by 1,12,10
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
select
  cast(date_format(date(conversion_time), 'yyyyMMdd') as integer) as sk_conversion_date,
  left(cast(city as varchar(20000)), 20000) as city,
  cast(id_amplitude * 1000 + nst_conversion as bigint) as unique_conversion_id,
  left(cast(array_join(collect_list(utm_source_medium), '; ') as varchar(20000)), 20000) as path_utm_source_medium,
  left(cast(array_join(collect_list(utm_source_medium_branded), '; ') as varchar(20000)), 20000) as path_utm_source_medium_branded,
  left(cast(array_join(collect_list(utm_source), '; ') as varchar(20000)), 20000) as path_utm_source,
  left(cast(array_join(collect_list(utm_medium), '; ') as varchar(20000)), 20000) as path_utm_medium,
  left(cast(array_join(collect_list(utm_campaign), '; ') as varchar(20000)), 20000) as path_utm_campaign,
  left(cast(array_join(collect_list(utm_content), '; ') as varchar(20000)), 20000) as path_utm_content,
  left(cast(array_join(collect_list(utm_term), '; ') as varchar(20000)), 20000) as path_utm_term
from touchpoints
where conversion_time >= current_date - interval '6' month
  and MONTHS_BETWEEN(session_start_time, conversion_time) <= 6
group by 1,2,3
order by 3