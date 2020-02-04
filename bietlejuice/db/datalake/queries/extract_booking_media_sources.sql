with cross_platform as (
	select
	    '170698' as app,
	    ts_event,
	    up_platform as platform,
	    ep_visit_code as visit_code,
	    coalesce(up_utm_source, '') as utm_source,
	    coalesce(up_utm_medium, '') as utm_medium,
	    coalesce(up_utm_campaign, '') as utm_campaign,
	    coalesce(up_utm_content, '') as utm_content,
	    coalesce(up_utm_term, '') as utm_term,
	    coalesce(up_adjust_network, '') as adjust_network,
	 	case
	 		when up_platform in ('web_desktop','web_mobile')
	 			then coalesce(up_utm_source, 'organic')
	 		else coalesce(up_adjust_network, '')
	 	end as media_source
	  from datalake_amplitude_clean_prod."170698_visit_schedule_confirmed_events"
),
ios as (
	select
			'156118' as app,
	    ts_event,
	    'ios' as platform,
	    coalesce(
				nullif(regexp_replace(cast(json_extract(event_properties, '$.Visita_id') as varchar), '\[|\]', ''),''),
				nullif(cast(json_extract(event_properties, '$.visit_code') as varchar),''),
				coalesce(cast(json_extract(event_properties, '$.visita_code') as varchar), '')
		) as visit_code,
		coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as utm_source,
		coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as utm_medium,
		coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as utm_campaign,
		coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as utm_content,
		coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as utm_term,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), '') as adjust_network,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), '') as media_source
	from datalake_amplitude_clean_prod.events
	where
		event_type = 'Confirmation-Visit_confirmed'
		and id_app = 156118
		and cast(ts_event as date) < cast('2017-08-17' as date)
),
web as (
	select
		'160023' as app,
		ts_event,
		case
			when device_type in ('Linux','Windows','Mac') then 'web_desktop'
			else 'web_mobile'
		end	as platform,
		coalesce(
				nullif(regexp_replace(cast(json_extract(event_properties, '$.Visita_id') as varchar), '\[|\]', ''),''),
				nullif(cast(json_extract(event_properties, '$.visit_code') as varchar),''),
				coalesce(cast(json_extract(event_properties, '$.visita_code') as varchar), '')
		) as visit_code,
		coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), 'organic') as utm_source,
		coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as utm_medium,
		coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as utm_campaign,
		coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as utm_content,
		coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as utm_term,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), '') as adjust_network,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), 'organic') as media_source
	from datalake_amplitude_clean_prod.events
	where event_type = 'Confirmation-Visit_confirmed'
				and id_app = 160023
				and cast(ts_event as date) < cast('2017-08-17' as date)
),
android as (
	select
		'157033' as app,
		ts_event,
		'android'	as platform,
		coalesce(
				nullif(regexp_replace(cast(json_extract(event_properties, '$.Visita_id') as varchar), '\[|\]', ''),''),
				nullif(cast(json_extract(event_properties, '$.visit_code') as varchar),''),
				coalesce(cast(json_extract(event_properties, '$.visita_code') as varchar), '')
		) as visit_code,
		coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as utm_source,
		coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as utm_medium,
		coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as utm_campaign,
		coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as utm_content,
		coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as utm_term,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), '') as adjust_network,
		coalesce(cast(json_extract(user_properties, '$["[adjust] network"]') as varchar), '') as media_source
	from datalake_amplitude_clean_prod.events
	where event_type = 'Confirmation-Visit_confirmed'
				and id_app = 157033
				and cast(ts_event as date) < cast('2017-08-23' as date)
),
merged_ios as (
	select
		i.*
	from
		ios i
	left join
		(
			select
				*
			from cross_platform
			where
				trim(platform) = 'ios'
						and cast(ts_event as date) >= cast('2017-08-17' as date)
		) cp
	on i.visit_code = cp.visit_code
	where cp.visit_code is null
),
merged_android as (
	select
		a.*
	from
		android a
	left join
		(
			select
				*
			from cross_platform
			where
				trim(platform) = 'android'
						and cast(ts_event as date) >= cast('2017-08-23' as date)
		) cp
	on a.visit_code = cp.visit_code
	where cp.visit_code is null
),
merged_web as (
	select
		w.*
	from
		web w
	left join
	(
			select
				*
			from cross_platform
			where
				trim(platform) in ('web_desktop','web_mobile')
						and cast(ts_event as date) >= cast('2017-08-17' as date)
		) cp
	on w.visit_code = cp.visit_code
	where cp.visit_code is null
),total as (
	select
		app as app,
		platform as app_type,
		ts_event as event_time,
		visit_code as visita_id,
		case 
		when media_source in ('','Organic') then 'organic'
		else media_source
		end as media_source,
		adjust_network,
		utm_source,
		utm_campaign,
		utm_medium,
		utm_content,
        utm_term,
		row_number() over (
			partition by visit_code
			order by cast(ts_event as date)
		) as rn
	from
		(
			select * from cross_platform
			union all
			select * from merged_ios
			union all
			select * from merged_android
			union all
			select * from merged_web
		) total
)
select
	app,
	app_type,
	event_time
	event_date,
	visita_id,
	media_source,
	adjust_network,
	utm_source,
	utm_campaign,
	utm_medium,
	utm_content,
    utm_term
from
	total
where 
	rn = 1 and visita_id is not null
