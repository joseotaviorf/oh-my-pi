with listing_page_viewed as (
    select
        min(ts_event) as ts_event,
  -- Using colaesce to identify merged users first
        coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
        id_session,
  -- Adapting syntax from SparkSQL to Presto
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
  -- Adapting syntax from SparkSQL to Presto
    from datalake_amplitude_clean_prod."170698_listing_page_viewed_events" damcs
  -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
home_page_viewed as (
    select
        min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
        coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
        id_session,
    -- Adapting syntax from SparkSQL to Presto
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
    -- Adapting syntax from SparkSQL to Presto
    from datalake_amplitude_clean_prod."170698_home_page_viewed_events" damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
search_results_page_viewed as (
    select
        min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
        coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
        id_session,
    -- Adapting syntax from SparkSQL to Presto
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
    -- Adapting syntax from SparkSQL to Presto
    from datalake_amplitude_clean_prod."170698_search_results_page_viewed_events" damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
schedule_page_viewed as (
    select
        min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
        coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
        id_session,
    -- Adapting syntax from SparkSQL to Presto
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
    -- Adapting syntax from SparkSQL to Presto
    from datalake_amplitude_clean_prod."170698_schedule_page_viewed_events" damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
visit_schedule_confirmed_aux as (
    select
        min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
        coalesce(merged_amplitude_id,id_amplitude) amplitude_id,
        id_session,
    -- Adapting syntax from SparkSQL to Presto
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term,
        json_extract_scalar(event_properties, '$.visit_code') as visit_code,
    -- Collecting city information about the houses
        json_extract_scalar(event_properties, '$.city') as city,
        json_extract_scalar(event_properties, '$.house_id') as house_id
    -- Adapting syntax from SparkSQL to Presto
    from datalake_amplitude_clean_prod."170698_visit_schedule_confirmed_events" damcs
    -- Joining merge users table to identify cross-device conversions
    left join datalake_raw.amplitude_merge_users_170698 amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8,9,10,11
),
visit_schedule_confirmed as (
  select
     vsca.ts_event,
     vsca.amplitude_id,
     vsca.id_session,
     vsca.utm_source,
     vsca.utm_medium,
     vsca.utm_campaign,
     vsca.utm_content,
     vsca.utm_term,
     vsca.visit_code,
     decph.city as city
  from visit_schedule_confirmed_aux vsca
  left join datalake_ebdb_clean_prod.house decph
  on cast(vsca.house_id as integer) = cast(decph.id as integer)
 ),
pre_events as (
    select
      *,
      null as visit_code,
  -- Adding the city to other events
      null as city
    from listing_page_viewed
    union all
    select
      *,
      null as visit_code,
    -- Adding the city to other events
      null as city
    from home_page_viewed
    union all
    select
      *,
      null as visit_code,
    -- Adding the city to other events
      null as city
    from search_results_page_viewed
    union all
    select
      *,
      null as visit_code,
    -- Adding the city to other events
      null as city
    from schedule_page_viewed
    union all
    select *
    from visit_schedule_confirmed
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
conversions as (
           -- retrieve conversion events per amplitude user
           -- conversion def: booking that resulted in a visit with tenant prospect present onsite
   select
       evt.ts_event,
       evt.amplitude_id,
  -- Adding the city
       evt.city,
       rank() over (partition by amplitude_id order by ts_event) as rnk_conversion
   from visit_schedule_confirmed evt
  -- Excluding the visit where the tenant was present condition
           -- join datalake_ebdb_clean.Visit v -- todo: replace by dim_visit after ODS migration
           --  on v.code = evt.visit_code
           -- join datalake_ebdb_clean.Booking b -- todo: replace by dim_booking after ODS migration
           --  on b.id_visit = v.id and b.is_visit_completed
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
         (case when evt.utm_campaign like '%branded%' then 'true'
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
      min(conv.ts_event) as conversion_time,
      min(conv.rnk_conversion) as nst_conversion
   from events evt
   join conversions conv
  -- Adapting to join by the coalesced id
    on conv.amplitude_id = evt.amplitude_id and conv.ts_event >= evt.ts_event
   group by 1,2,3,4,5,6,7,8,9,10,11
  order by 1,12,10
)
         -- aggregate touchpoints to unique conversions with their path concatenated in one column
         -- conversions July - September 2019
         -- lookback window of 6 month
select
   cast(date_format(date(conversion_time), '%Y%m%d') as integer) as sk_conversion_date,
   -- Adding the city data
   cast(city as varchar(20000)) as city,
   -- Using the coalesced id
   cast(amplitude_id * 1000 + nst_conversion as bigint) as unique_conversion_id,
   -- Adapting syntax from SparkSQL to Presto
   cast(array_join(array_agg(utm_source_medium), '; ') as varchar(20000)) as path_utm_source_medium,
   cast(array_join(array_agg(utm_source_medium_branded), '; ') as varchar(20000)) as path_utm_source_medium_branded,
   cast(array_join(array_agg(utm_source), '; ') as varchar(20000)) as path_utm_source,
   cast(array_join(array_agg(utm_medium), '; ') as varchar(20000)) as path_utm_medium,
   cast(array_join(array_agg(utm_campaign), '; ') as varchar(20000)) as path_utm_campaign,
   cast(array_join(array_agg(utm_content), '; ') as varchar(20000)) as path_utm_content,
   cast(array_join(array_agg(utm_term), '; ') as varchar(20000)) as path_utm_term
from touchpoints
where conversion_time >= date('2019-11-01')
  and date_diff('month', session_start_time, conversion_time) <= 6
group by 1, 2,3
