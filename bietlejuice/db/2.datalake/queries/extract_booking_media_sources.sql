with cross_platform as (
	select
		app,
		event_time,
		u_platform as platform,
		coalesce(
			nullif(regexp_replace(e__visita_id, '\[|\]', ''),''),
			nullif(e_visit_code,''),
			e_visita_code
		) as visit_code,
		u_utm_source as utm_source,
		u_utm_medium as utm_medium,
		u_utm_campaign as utm_campaign,
		u_adjust_network as adjust_network,
		case
			when u_platform in ('web_desktop','web_mobile')
				then coalesce(u_utm_source,'organic')
			else u_adjust_network
		end as media_source
	from
		datalake_clean.amplitude_events
	where
		et = 'visit_schedule_confirmed'
	and trim(app) = '170698'
),
ios as (
	select
		app,
		event_time,
		'ios' as platform,
		coalesce(
			nullif(regexp_replace(e__visita_id, '\[|\]', ''),''),
			nullif(e_visit_code,''),
			e_visita_code
		) as visit_code,
		u_utm_source as utm_source,
		u_utm_medium as utm_medium,
		u_utm_campaign as utm_campaign,
		u_adjust_network as adjust_network,
		u_adjust_network as media_source
	from
		datalake_clean.amplitude_events
	where
		et = 'Confirmation-Visit_confirmed'
	and trim(app) = '156118'
	and
	cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) < cast('2017-08-17' as date)
),
web as (
	select
		app,
		event_time,
		case
			when device_type in ('Linux','Windows','Mac') then 'web_desktop'
			else 'web_mobile'
		end	as platform,
		coalesce(
			nullif(regexp_replace(e__visita_id, '\[|\]', ''),''),
			nullif(e_visit_code,''),
			e_visita_code
		) as visit_code,
		coalesce(u_utm_source,'organic') as utm_source,
		u_utm_medium as utm_medium,
		u_utm_campaign as utm_campaign,
		u_adjust_network as adjust_network,
		coalesce(u_utm_source,'organic') as media_source
	from
		datalake_clean.amplitude_events
	where
		et = 'Confirmation-Visit_confirmed'
	and trim(app) = '160023'
	and
	cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) < cast('2017-08-17' as date)
),
android as (
	select
		app,
		event_time,
		'android' as platform,
		coalesce(
			nullif(regexp_replace(e__visita_id, '\[|\]', ''),''),
			nullif(e_visit_code,''),
			e_visita_code
		) as visit_code,
		u_utm_source as utm_source,
		u_utm_medium as utm_medium,
		u_utm_campaign as utm_campaign,
		u_adjust_network as adjust_network,
		u_adjust_network as media_source
	from
		datalake_clean.amplitude_events
	where
		et = 'Confirmation-Visit_confirmed'
	and trim(app) = '157033'
	and
	cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) < cast('2017-08-23' as date)
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
			and
			cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) >= cast('2017-08-17' as date)
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
			and
			cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) >= cast('2017-08-23' as date)
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
			and
			cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date) >= cast('2017-08-17' as date)
		) cp
	on w.visit_code = cp.visit_code
	where cp.visit_code is null
),total as (
	select
		app as app,
		platform as app_type,
		cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as event_time,
		visit_code as visita_id,
		case 
		when media_source in ('','Organic') then 'organic'
		else media_source
		end as media_source,
		adjust_network,
		utm_source,
		utm_campaign,
		utm_medium,
		row_number() over ( 
			partition by visit_code 
			order by cast(cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date)
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
	utm_medium
from
	total
where 
	rn = 1 and visita_id is not null
