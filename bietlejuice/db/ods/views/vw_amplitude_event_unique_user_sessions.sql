drop view if exists vw_amplitude_event_unique_user_sessions;
create view vw_amplitude_event_unique_user_sessions as
select
  (a.message #>> '{app}')::integer as app_id,
  (a.message ->> 'amplitude_id')::bigint as amplitude_id,
  -- a.message ->> 'session_id' as session_id,
  max(coalesce(a.message #>> '{user_properties, Usuario_id}', a.message ->> 'user_id', '0'))::bigint as user_id,
  -- a.message #>> '{user_properties, email}' as email,
  a.message #>> '{user_properties, initial_referrer}' as initial_referrer,
  a.message #>> '{user_properties, initial_referring_domain}' as initial_referring_domain,
  a.message #>> '{user_properties, initial_utm_campaign}' as initial_utm_campaign,
  a.message #>> '{user_properties, initial_utm_source}' as initial_utm_source,
  a.message #>> '{user_properties, initial_utm_medium}' as initial_utm_medium,
  a.message #>> '{user_properties, initial_utm_content}' as initial_utm_content,
  a.message #>> '{user_properties, initial_utm_term}' as initial_utm_term,
  a.message #>> '{user_properties, referrer}' as referrer,
  a.message #>> '{user_properties, referring_domain}' as referring_domain,
  a.message #>> '{user_properties, utm_campaign}' as utm_campaign,
  a.message #>> '{user_properties, utm_source}' as utm_source,
  a.message #>> '{user_properties, utm_medium}' as utm_medium,
  a.message #>> '{user_properties, utm_content}' as utm_content,
  a.message #>> '{user_properties, utm_term}' as utm_term,

  last_value(a.message #>> '{user_properties, [adjust] network}') over ()::text as network,
  last_value(a.message #>> '{user_properties, [adjust] adgroup}') over ()::text as adgroup,
  last_value(a.message #>> '{user_properties, [adjust] campaign}') over ()::text as adjust_campaign,

  last_value(a.message #>> '{user_properties, Total_confirmed_visits}') over ()::integer  as total_confirmed_visits,
  last_value(a.message #>> '{user_properties, Total_viewed_listings}') over ()::integer  as total_viewed_listings,
  last_value(a.message #>> '{user_properties, Total_booking_clicks}') over ()::integer  as total_booking_clicks,
  last_value(a.message #>> '{user_properties, Total_canceled_visits}') over ()::integer  as total_cancelled_visits,
  last_value(a.message #>> '{user_properties, Total_map_price_flag_clicks}') over ()::integer  as total_map_price_flag_clicks,

  array_agg_notnull(
    coalesce(
      case
          when (replace(replace(a.message #>> '{event_properties, Imovel_id}','[', ''),']',''))::integer >= 892700000
              THEN (replace(replace(a.message #>> '{event_properties, Imovel_id}','[', ''),']',''))::integer
          else 892700000 + (replace(replace(a.message #>> '{event_properties, Imovel_id}','[', ''),']',''))::integer
      end,
      case
          when (replace(replace(a.message #>> '{event_properties, imovel_id}','[', ''),']',''))::integer >= 892700000
              THEN (replace(replace(a.message #>> '{event_properties, imovel_id}','[', ''),']',''))::integer
          else 892700000 + (replace(replace(a.message #>> '{event_properties, imovel_id}','[', ''),']',''))::integer
      end
    )
  )  as all_imovel_id,

  array_agg_notnull(a.message #>> '{event_type}') as all_events,

  min(a.message #>> '{event_time}')::timestamp  as min_event_time,
  max(a.message #>> '{event_time}')::timestamp  as max_event_time

from
  amplitude_event a

group by
  a.message #>> '{app}',
  a.message ->> 'amplitude_id',
  coalesce(a.message #>> '{user_properties, Usuario_id}', a.message ->> 'user_id', '0'),
  a.message #>> '{user_properties, initial_referrer}',
  a.message #>> '{user_properties, initial_referring_domain}',
  a.message #>> '{user_properties, initial_utm_campaign}',
  a.message #>> '{user_properties, initial_utm_source}',
  a.message #>> '{user_properties, initial_utm_medium}',
  a.message #>> '{user_properties, initial_utm_content}',
  a.message #>> '{user_properties, initial_utm_term}',
  a.message #>> '{user_properties, referrer}',
  a.message #>> '{user_properties, referring_domain}',
  a.message #>> '{user_properties, utm_campaign}',
  a.message #>> '{user_properties, utm_source}',
  a.message #>> '{user_properties, utm_medium}',
  a.message #>> '{user_properties, utm_content}',
  a.message #>> '{user_properties, utm_term}',
  a.message #>> '{user_properties, [adjust] network}',
  a.message #>> '{user_properties, [adjust] adgroup}',
  a.message #>> '{user_properties, [adjust] campaign}',
  a.message #>> '{user_properties, Total_confirmed_visits}',
  a.message #>> '{user_properties, Total_viewed_listings}',
  a.message #>> '{user_properties, Total_booking_clicks}',
  a.message #>> '{user_properties, Total_canceled_visits}',
  a.message #>> '{user_properties, Total_map_price_flag_clicks}'
;