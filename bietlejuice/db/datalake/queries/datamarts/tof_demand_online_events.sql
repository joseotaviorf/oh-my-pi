with
last_version_listings as (
select
	id_house,
	sk_house_listing,
	cast(nullif(cast(ts_listing_version_start as varchar), '') as timestamp) as ts_listing_version_start,
	cast(nullif(cast(ts_listing_version_end as varchar), '') as timestamp) as ts_listing_version_end
from datalake_clean.ods_dim_house_listing
where cast(nullif(cast(version as varchar), '') as bigint) > 0
)
select
  date_trunc('week', date(ts_event)) as event_week,
  date(ts_event) as event_date,
	ts_event as event_timestamp,
	ev.id_user,
	ev.id_amplitude,
	trim(json_extract_scalar(event_properties, '$["house_id"]')) as house_id,
	lvl.sk_house_listing,
	json_extract_scalar(event_properties, '$.agent_id') as agent_id,
	case when trim(event_type) = 'listing_page_viewed' then 1 else 0 end as listing_page_viewed,
	case when trim(event_type) = 'pilot_cw_button_clicked' then 1 else 0 end as talk_to_agent_button_clicked,
	case when trim(event_type) = 'piloto_cw_dialog_viewed' then 1 else 0 end as talk_to_agent_dialog_viewed,
	case when trim(event_type) = 'piloto_cw_message_sent' then 1 else 0 end as talk_to_agent_message_sent,
  case when trim(event_type) = 'piloto_cw_message_sent' then substr(regexp_extract(replace(regexp_replace(json_extract_scalar(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{9}))).*'),4) else null end as talk_to_agent_message_content,
  case when trim(event_type) = 'offer_submitted' then 1 else 0 end as offer_submitted,
  cast(json_extract_scalar(user_properties, '$.utm_source') as varchar) as utm_source,
	cast(json_extract_scalar(user_properties, '$.utm_medium') as varchar) as utm_medium,
	cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar) as utm_campaign,
	cast(json_extract_scalar(user_properties, '$.utm_content') as varchar) as utm_content,
	cast(json_extract_scalar(user_properties, '$.utm_term') as varchar) as utm_term
from datalake_amplitude_clean_prod.events ev
left join last_version_listings lvl
  on trim(json_extract_scalar(ev.event_properties, '$["house_id"]'))  = cast(lvl.id_house as varchar)
  and ts_event between ts_listing_version_start and (coalesce(ts_listing_version_end, current_timestamp) - interval '1' second)
where
	date(ts_event) >= current_date - interval '45' day
	and trim(event_type) in (
		'listing_page_viewed',
		'pilot_cw_button_clicked',
		'piloto_cw_dialog_viewed',
		'piloto_cw_message_sent',
		'offer_submitted'
	)
