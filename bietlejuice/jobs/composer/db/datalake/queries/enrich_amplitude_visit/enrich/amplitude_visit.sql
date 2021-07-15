with cross_platform as (
  select
    '170698' as id_app,
    ts_event,
    up_platform as app_type,
    ep_visit_code as id_visit,
    up_utm_source as utm_source,
    up_utm_medium as utm_medium,
    up_utm_campaign as utm_campaign,
    up_utm_content as utm_content,
    up_utm_term as utm_term,
    up_adjust_network as adjust_network,
    coalesce(
      nullif(
        case
          when up_platform in ("web_desktop", "web_mobile")
            then up_utm_source
          else up_adjust_network
        end,
      "Organic"),
    "organic")
    as media_source,
    row_number() over (
      partition by ep_visit_code
      order by cast(ts_event as date)
    ) as rn
  from
    datalake_amplitude_clean.170698_visit_schedule_confirmed_events
)
select
  id_app,
  id_visit,
  app_type,
  coalesce(media_source, 'Unknown') as media_source,
  adjust_network,
  utm_source,
  utm_campaign,
  utm_medium,
  utm_content,
  utm_term,
  coalesce(
    (
      (
        UPPER(utm_campaign) like '%BRANDED%'
        or UPPER(utm_campaign) like '%INSTITUCIONAL%'
      )
      and lower(utm_campaign) not like '%non-branded%'
    ), false
  ) as is_branded,
  -- temporary column to join with taxonomy,
  -- it can be replaced by the usage of previous column but
  -- some refactoring will be needed in demand taxonomy
  case when
    (
      UPPER(utm_campaign) like '%BRANDED%'
      or UPPER(utm_campaign) like '%INSTITUCIONAL%'
    )
    and lower(utm_campaign) not like '%non-branded%'
    then 'Branded'
    else 'Outro'
  end as branded,
  ts_event
from
  cross_platform
where
  rn = 1
  and id_visit is not null