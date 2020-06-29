with offer_submitted_conversions as (
  select distinct
    osa.ts_event,
    osa.amplitude_id,
    osa.id_session,
    osa.utm_source,
    osa.utm_medium,
    osa.utm_campaign,
    osa.utm_content,
    osa.utm_term,
    osa.visit_code,
    dcodr.city_group as city
  from datamarts.offer_submitted_aux osa
  left join datalake_clean.ods_fact_house_listings clofhl
    on cast(osa.house_id as integer) = cast(clofhl.sk_house_listing as BIGINT)/1000
  left join datalake_clean.ods_dim_region dcodr
    on cast(clofhl.sk_region as integer) = cast(dcodr.sk_region as integer)
  where ts_event >= current_date - interval '6' month
  group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
offer_submitted_sessions as (
  select distinct
    min(osc.ts_event) as ts_event,
    osc.amplitude_id,
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
  select
    *
  from datamarts.listing_page_viewed_events
  union all
    select
      *
    from datamarts.home_page_viewed_events
  union all
    select
      *
    from datamarts.search_results_page_viewed_events
  union all
    select
      *
    from datamarts.schedule_page_viewed_events
  union all
    select *
    from offer_submitted_sessions
),
events_rank as (
  select
    min(ts_event) as ts_event,
    -- Using the colaesced id to get the rank
    amplitude_id,
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
    and p.amplitude_id=r.amplitude_id
    and p.id_session=r.id_session
),
conversion_sessions_unique as (
  -- retrieve conversion sessions, indicating last conversion session
  select
    oss.id_session,
    oss.amplitude_id,
    er.ts_event as ts_session,
    nullif(lag(er.ts_event) over (partition by oss.amplitude_id order by er.ts_event), er.ts_event) as ts_last_session
  from offer_submitted_sessions oss
  join events_rank er on er.amplitude_id = oss.amplitude_id and er.id_session = oss.id_session
  group by 1, 2, 3
),
conversion_events as (
  -- retrieve conversion events together with their session info
  select
    osc.ts_event,
    osc.id_session,
    osc.amplitude_id,
    osc.visit_code,
    osc.city,
    csu.ts_session,
    csu.ts_last_session,
    rank() over (partition by osc.amplitude_id order by osc.ts_event) as rnk_conversion
  from offer_submitted_conversions osc
  join conversion_sessions_unique csu on csu.amplitude_id = osc.amplitude_id and csu.id_session = osc.id_session  
),
touchpoints as (
  -- aggregate events to attributed sessions (=touchpoints)
  -- determine for each session the start_time and the time of closest conversion event
  -- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
  select
    -- Collect the coalesced id
    evt.amplitude_id,
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
  	on evt.amplitude_id = conv.amplitude_id
  	and evt.ts_event > coalesce(conv.ts_last_session, date('2000-01-01')) -- join events that happened between last conversion and current conversion
    and evt.ts_event <= conv.ts_session
  where date_diff('month', evt.ts_event, conv.ts_event) <= 6
  group by 1,2,3,4,5,6,7,8,9,10,11,12,13
  order by 1,12,10
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
select
  cast(date_format(date(conversion_time), '%Y%m%d') as integer) as sk_conversion_date,
  -- Adding the city data
  cast(city as varchar(20000)) as city,
  -- Using the coalesced id
  cast(amplitude_id * 1000 + nst_conversion as bigint) as unique_conversion_id,
  cast(array_join(array_agg(utm_source_medium), '; ') as varchar(20000)) as path_utm_source_medium,
  cast(array_join(array_agg(utm_source_medium_branded), '; ') as varchar(20000)) as path_utm_source_medium_branded,
  cast(array_join(array_agg(utm_source), '; ') as varchar(20000)) as path_utm_source,
  cast(array_join(array_agg(utm_medium), '; ') as varchar(20000)) as path_utm_medium,
  cast(array_join(array_agg(utm_campaign), '; ') as varchar(20000)) as path_utm_campaign,
  cast(array_join(array_agg(utm_content), '; ') as varchar(20000)) as path_utm_content,
  cast(array_join(array_agg(utm_term), '; ') as varchar(20000)) as path_utm_term
from touchpoints
group by 1, 2,3
order by 3