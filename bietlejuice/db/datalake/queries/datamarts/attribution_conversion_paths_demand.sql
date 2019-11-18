with events as (
	-- retrieve events that reflect entry points (web only)
	-- use entrance_uri user property to identify sessions UTM (more accurate than utm_ user props)
	-- merge amplitude users to leading amplitude user (NEEDS MANUAL UPDATE) 
	select
	    cast(regexp_extract(evt.event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') as timestamp) as event_time,
	    evt.amplitude_id,
	    umg.merged_amplitude_id,
	    coalesce(umg.merged_amplitude_id, evt.amplitude_id) as leading_amplitude_id,
	    evt.session_id,
	    evt.event_type,	    
	    coalesce(split_part(split_part(json_extract_scalar(evt.user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
		coalesce(split_part(split_part(json_extract_scalar(evt.user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
		coalesce(split_part(split_part(json_extract_scalar(evt.user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
		coalesce(split_part(split_part(json_extract_scalar(evt.user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
		coalesce(split_part(split_part(json_extract_scalar(evt.user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term,
		case when evt.event_type = 'visit_schedule_confirmed' then json_extract_scalar(evt.event_properties, '$.visit_code') end as visit_code,
		rank() over (partition by evt.amplitude_id, evt.session_id order by evt.event_time asc) as rnk_event_of_session
	from datalake_amplitude_clean_prod.events evt
	left join datalake_raw.amplitude_merge_users_170698 umg on umg.amplitude_id = evt.amplitude_id
	where evt.year = 2019 
	and evt.event_type in ('listing_page_viewed', 'home_page_viewed', 'search_results_page_viewed', 'schedule_page_viewed', 'visit_schedule_confirmed') 
	and evt.app = 170698
	and evt.platform = 'Web'
),
conversions as (
	-- retrieve conversion events per amplitude user
	-- conversion def: booking that resulted in a visit with tenant prospect present onsite
	select
	    evt.event_time,
	    evt.amplitude_id,
	    rank() over (partition by amplitude_id order by event_time) as rnk_conversion
	from events evt
	join datalake_clean.ods_dim_visit dv on dv.cd_visit = evt.visit_code
	join datalake_clean.ods_dim_booking db on db.id_visit = dv.id_visit and db.status = 'Realizado' and db.visitor_arrived = '1'
	where event_type = 'visit_schedule_confirmed'
),
touchpoints as (
	-- aggregate events to attributed sessions (=touchpoints)
	-- determine for each session the start_time and the time of closest conversion event
	-- order matters for building seq. paths - user ASC > Nst conversion ASC > Nst session_start ASC
	select 
		evt.amplitude_id,
		evt.session_id,
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
		evt.event_time as session_start_time,
		min(conv.event_time) as conversion_time,
		min(conv.rnk_conversion) as nst_conversion
	from events evt
	join conversions conv on conv.amplitude_id = evt.amplitude_id and conv.event_time >= evt.event_time
	where evt.rnk_event_of_session = 1
	group by 1,2,3,4,5,6,7,8,9,10
	order by 1,11,10
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
-- conversions July - September 2019
-- lookback window of 6 month
select 
	cast(date_format(date(conversion_time), '%Y%m%d') as integer) as sk_conversion_date,
	cast(amplitude_id * 1000 + nst_conversion as bigint) as unique_conversion_id,
	array_join(array_agg(utm_source_medium), '; ') as path_utm_source_medium,
	array_join(array_agg(utm_source_medium_branded), '; ') as path_utm_source_medium_branded,
	array_join(array_agg(utm_source), '; ') as path_utm_source,
	array_join(array_agg(utm_medium), '; ') as path_utm_medium,
	array_join(array_agg(utm_campaign), '; ') as path_utm_campaign,
	array_join(array_agg(utm_content), '; ') as path_utm_content,
	array_join(array_agg(utm_term), '; ') as path_utm_term
from touchpoints
where conversion_time >= date('2019-07-01')
and date_diff('month', session_start_time, conversion_time) <= 6
group by 1, 2;
