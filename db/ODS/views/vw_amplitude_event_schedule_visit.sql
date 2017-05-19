drop view if exists vw_amplitude_event_schedule_visit;
create view vw_amplitude_event_schedule_visit as
select distinct
	a.message #>> '{uuid}' as uuid,
  	a.message #>> '{app}' as app_id,
    a.message #>> '{event_type}' as event_type,
    a.message #>> '{event_time}' as event_time,
  	a.message ->> 'amplitude_id' as amplitude_id,
  	a.message ->> 'user_id' as user_id,

    a.message #>> '{user_properties, email}' as email,

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
    ) as imovel_id,

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

    a.message #>> '{user_properties, Total_confirmed_visits}' as Total_confirmed_visits,
    a.message #>> '{user_properties, Total_viewed_listings}' as Total_viewed_listings,
    a.message #>> '{user_properties, Total_booking_clicks}' as Total_booking_clicks

from
	amplitude_event a
where
	a.message ->> 'event_type' in ('Preview-Schedule_visit', 'Listing-Clicks_schedule_visit')
;