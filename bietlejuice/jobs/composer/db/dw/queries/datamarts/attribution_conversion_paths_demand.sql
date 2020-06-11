with listing_page_viewed as (
    select
        min(ts_event) as ts_event,
        coalesce(merged_amplitude_id, id_amplitude) as id_amplitude,
        id_session,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
        null as visit_code,
        null as city
    from datalake_amplitude_clean_staging.`170698_listing_page_viewed_events` damcs
    left join datalake_amplitude_raw.`170698_user_merge` amu
        on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
home_page_viewed as (
    select
        min(ts_event) as ts_event,
        coalesce(merged_amplitude_id, id_amplitude) as id_amplitude,
        id_session,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
        null as visit_code,
        null as city
    from datalake_amplitude_clean_staging.`170698_home_page_viewed_events` damcs
    left join datalake_amplitude_raw.`170698_user_merge` amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
search_results_page_viewed as (
    select
        min(ts_event) as ts_event,
        coalesce(merged_amplitude_id, id_amplitude) as id_amplitude,
        id_session,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
        null as visit_code,
        null as city
    from datalake_amplitude_clean_staging.`170698_search_results_page_viewed_events` damcs
    left join datalake_amplitude_raw.`170698_user_merge` amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
schedule_page_viewed as (
    select
        min(ts_event) as ts_event,
        coalesce(merged_amplitude_id,id_amplitude) as id_amplitude,
        id_session,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
        null as visit_code,
        null as city
    from datalake_amplitude_clean_staging.`170698_schedule_page_viewed_events` damcs
    left join datalake_amplitude_raw.`170698_user_merge` amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
visit_schedule_confirmed_aux as (
    select
        min(ts_event) as ts_event,
        coalesce(merged_amplitude_id, id_amplitude) as id_amplitude,
        id_session,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as utm_content,
        coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as utm_term,
        get_json_object(event_properties, '$.visit_code') as visit_code,
        get_json_object(event_properties, '$.house_id') as house_id
    from datalake_amplitude_clean_staging.`170698_visit_schedule_confirmed_events` damcs
    left join datalake_amplitude_raw.`170698_user_merge` amu
      on damcs.id_amplitude = amu.amplitude_id
    where year >= 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8,9,10
),
visit_schedule_confirmed as (
  select
     vsca.ts_event,
     vsca.id_amplitude,
     vsca.id_session,
     vsca.utm_source,
     vsca.utm_medium,
     vsca.utm_campaign,
     vsca.utm_content,
     vsca.utm_term,
     vsca.visit_code,
     decph.city as city
  from visit_schedule_confirmed_aux vsca
  left join datalake_ebdb_clean.house decph
    on cast(vsca.house_id as integer) = cast(decph.id as integer)
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
    select * from visit_schedule_confirmed
),
events_rank as (
    select
      min(ts_event) as ts_event,
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
    on p.ts_event = r.ts_event
       and p.id_amplitude = r.id_amplitude
       and p.id_session = r.id_session
),
conversions as (
   -- retrieve conversion events per amplitude user
   -- conversion def: booking that resulted in a visit with tenant prospect present onsite
   select
       evt.ts_event,
       evt.id_amplitude,
       evt.city,
       rank() over (partition by id_amplitude order by ts_event) as rnk_conversion
   from visit_schedule_confirmed evt
),
touchpoints as (
   -- aggregate events to attributed sessions (=touchpoints)
   -- determine for each session the start_time and the time of closest conversion event
   -- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
   select
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
      min(conv.ts_event) as conversion_time,
      min(conv.rnk_conversion) as nst_conversion
   from events evt
   join conversions conv
    on conv.id_amplitude = evt.id_amplitude and conv.ts_event >= evt.ts_event
   group by 1,2,3,4,5,6,7,8,9,10,11
  order by 1,12,10
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
-- conversions July - September 2019
-- lookback window of 6 month
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
where conversion_time >= date('2019-11-01')
  and cast(months_between(conversion_time, session_start_time) as int) <= 6
group by 1, 2, 3