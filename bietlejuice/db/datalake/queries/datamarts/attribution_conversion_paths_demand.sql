with listing_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign
  from datalake_amplitude_clean_prod."170698_listing_page_viewed_events" damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
  where date(cast(year as varchar) || '-' || cast(month as varchar) || '-' || cast(day as varchar)) >= current_date - interval '9' month
  group by 2,3,4,5,6
),
home_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign
  from datalake_amplitude_clean_prod."170698_home_page_viewed_events" damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
  where date(cast(year as varchar) || '-' || cast(month as varchar) || '-' || cast(day as varchar)) >= current_date - interval '9' month
  group by 2,3,4,5,6
),
search_results_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign
  from datalake_amplitude_clean_prod."170698_search_results_page_viewed_events" damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
  where date(cast(year as varchar) || '-' || cast(month as varchar) || '-' || cast(day as varchar)) >= current_date - interval '9' month
  group by 2,3,4,5,6
),
schedule_page_viewed as (
  select
    min(ts_event) as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) as amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign
  from datalake_amplitude_clean_prod."170698_schedule_page_viewed_events" damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
  where date(cast(year as varchar) || '-' || cast(month as varchar) || '-' || cast(day as varchar)) >= current_date - interval '9' month
  group by 2,3,4,5,6
),
contract_docusign_signed_aux as (
  select
    ts_event as ts_event,
    -- Using colaesce to identify merged users first
    coalesce(merged_amplitude_id,id_amplitude) amplitude_id,
    id_session,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as utm_source,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as utm_medium,
    coalesce(nullif(regexp_extract(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as utm_campaign,
    json_extract_scalar(event_properties, '$.house_id') as house_id
  from datalake_amplitude_clean_prod.events damcs
  -- Joining merge users table to identify cross-device conversions
  left join datalake_raw.amplitude_merge_users_170698 amu
    on damcs.id_amplitude = amu.amplitude_id
  where date(cast(year as varchar) || '-' || cast(month as varchar) || '-' || cast(day as varchar)) >= current_date - interval '3' month
    and id_app = 170698 
    and event_type = 'contract_docusign_signed'
  group by 1,2,3,4,5,6,7
),
contract_docusign_signed_conversions as (
  select distinct
    csa.ts_event,
    csa.amplitude_id,
    csa.id_session,
    csa.utm_source,
    csa.utm_medium,
    csa.utm_campaign,
    clofhl.sk_region
  from contract_docusign_signed_aux csa
  left join datalake_clean.ods_fact_house_listings clofhl
    on cast(csa.house_id as integer) = cast(clofhl.sk_house_listing as BIGINT) / 1000
  group by 1, 2, 3, 4, 5, 6, 7
),
contract_docusign_signed_sessions as (
  select distinct
    min(csc.ts_event) as ts_event,
    csc.amplitude_id,
    csc.id_session,
    csc.utm_source,
    csc.utm_medium,
    csc.utm_campaign
  from contract_docusign_signed_conversions csc
  group by 2, 3, 4, 5, 6
),
pre_events as (
  select
    *
  from listing_page_viewed
  union all
    select
      *
    from home_page_viewed
  union all
    select
      *
    from search_results_page_viewed
  union all
    select 
      *
    from schedule_page_viewed
  union all
    select *
    from contract_docusign_signed_sessions
),
first_event_on_session as (
  select
    min(ts_event) as ts_event,
    amplitude_id,
    id_session
  from pre_events
  group by 2,3
),
events as (
  select
    p.*
  from pre_events p
  inner join first_event_on_session r
    on p.ts_event=r.ts_event
    and p.amplitude_id=r.amplitude_id
    and p.id_session=r.id_session
),
conversion_sessions_unique as (
  -- retrieve conversion sessions, indicating last conversion session
  select
    css.id_session,
    css.amplitude_id,
    er.ts_event as ts_session,
    nullif(lag(er.ts_event) over (partition by css.amplitude_id order by er.ts_event), er.ts_event) as ts_last_session
  from contract_docusign_signed_sessions css
  join first_event_on_session er on er.amplitude_id = css.amplitude_id and er.id_session = css.id_session
  group by 1, 2, 3
),
conversion_events as (
  -- retrieve conversion events together with their session info
  select 
    csc.ts_event,
    csc.id_session,
    csc.amplitude_id,
    csc.sk_region,
    csu.ts_session,
    csu.ts_last_session,
    rank() over (partition by csc.amplitude_id order by csc.ts_event) as rnk_conversion
  from contract_docusign_signed_conversions csc
  join conversion_sessions_unique csu on csu.amplitude_id = csc.amplitude_id and csu.id_session = csc.id_session  
),
touchpoints as (
  -- aggregate events to attributed sessions (=touchpoints)
  -- determine for each session the start_time and the time of closest conversion event
  -- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
  select
    -- Collect the coalesced id
    evt.amplitude_id,
    evt.id_session,
    evt.utm_source || '/' || evt.utm_medium || '/' ||
    (case when evt.utm_campaign like '%branded%' and lower(evt.utm_campaign) not like '%non-branded%' then 'true'
    when evt.utm_campaign like '%institucional%' then 'true'
    else 'false' end)
    as utm_source_medium_branded,
    evt.ts_event as session_start_time,
    conv.sk_region,
    conv.ts_event as conversion_time,
    conv.rnk_conversion as nst_conversion
  from conversion_events conv
  left join events evt
  	on evt.amplitude_id = conv.amplitude_id
  	and evt.ts_event > coalesce(conv.ts_last_session, date('2000-01-01')) -- join events that happened between last conversion and current conversion
    and evt.ts_event <= conv.ts_session 
  group by 1,2,3,4,5,6,7
  order by 1,6,4
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
select
  cast(date_format(date(conversion_time), '%Y%m%d') as integer) as sk_conversion_date,
  -- Adding the sk_region data
  sk_region,
  -- Using the coalesced id
  cast(amplitude_id * 1000 + nst_conversion as bigint) as unique_conversion_id,
  cast(array_join(array_agg(utm_source_medium_branded), '; ') as varchar(20000)) as path_utm_source_medium_branded
from touchpoints
where conversion_time >= current_date - interval '3' month
  and date_diff('month', session_start_time, conversion_time) <= 6
group by 1, 2,3
