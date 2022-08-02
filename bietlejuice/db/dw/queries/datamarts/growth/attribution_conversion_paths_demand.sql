WITH 
contract_docusign_signed_conversions AS (
    SELECT
        csa.ts_event,
        csa.id_amplitude,
        csa.id_session,
        csa.id_house,
        csa.utm_source,
        csa.utm_medium,
        csa.utm_campaign,
        csa.utm_content,
        csa.utm_term,
        clofhl.sk_region
    FROM datalake_amplitude_page_viewed_events.contract_docusign_signed_events csa
    LEFT JOIN dw_public.fact_house_listings clofhl
        ON CAST(csa.id_house AS INTEGER) = CAST(clofhl.sk_house_listing AS BIGINT) / 1000
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
contract_docusign_signed_sessions AS (
  SELECT
    csc.id_amplitude,
    csc.id_session,
    csc.id_house,
    csc.utm_source,
    csc.utm_medium,
    csc.utm_campaign,
    csc.utm_content,
    csc.utm_term,
    min(csc.ts_event) AS ts_event
  FROM contract_docusign_signed_conversions csc
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
pre_events AS (
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM datalake_amplitude_page_viewed_events.listing_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM datalake_amplitude_page_viewed_events.home_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM datalake_amplitude_page_viewed_events.search_results_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM datalake_amplitude_page_viewed_events.schedule_page_viewed
    UNION ALL
    SELECT
      id_amplitude,
      id_session,
      id_house,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_content,
      utm_term,
      ts_event
    FROM contract_docusign_signed_sessions
),
first_event_on_session as (
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
  inner join first_event_on_session r
    on p.ts_event=r.ts_event
    and p.id_amplitude=r.id_amplitude
    and p.id_session=r.id_session
),
conversion_sessions_unique as (
  -- retrieve conversion sessions, indicating last conversion session
  select
    css.id_session,
    css.id_amplitude,
    er.ts_event as ts_session,
    nullif(lag(er.ts_event) over (partition by css.id_amplitude order by er.ts_event), er.ts_event) as ts_last_session
  from contract_docusign_signed_sessions css
  join first_event_on_session er on er.id_amplitude = css.id_amplitude and er.id_session = css.id_session
  group by 1, 2, 3
),
conversion_events as (
  -- retrieve conversion events together with their session info
  select 
    csc.ts_event,
    csc.id_session,
    csc.id_amplitude,
    csc.sk_region,
    csu.ts_session,
    csu.ts_last_session,
    rank() over (partition by csc.id_amplitude order by csc.ts_event) as rnk_conversion
  from contract_docusign_signed_conversions csc
  join conversion_sessions_unique csu on csu.id_amplitude = csc.id_amplitude and csu.id_session = csc.id_session  
),
touchpoints as (
  -- aggregate events to attributed sessions (=touchpoints)
  -- determine for each session the start_time and the time of closest conversion event
  -- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
  select
    -- Collect the coalesced id
    evt.id_amplitude,
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
  	on evt.id_amplitude = conv.id_amplitude
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
  cast(id_amplitude * 1000 + nst_conversion as bigint) as unique_conversion_id,
  cast(array_join(array_agg(utm_source_medium_branded), '; ') as varchar(20000)) as path_utm_source_medium_branded,
  NOW() AS ts_load
from touchpoints
where conversion_time >= current_date - interval '3' month
  and date_diff('month', session_start_time, conversion_time) <= 6
group by 1, 2,3
