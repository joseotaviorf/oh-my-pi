with listing_page_viewed as (
    select 
        min(ts_event) as ts_event, 
        id_amplitude, 
        id_session,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
        
    from datalake_amplitude_clean_staging_prod."170698_listing_page_viewed_events"
    where year = 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
home_page_viewed as (
    select 
        min(ts_event) as ts_event, 
        id_amplitude, 
        id_session,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
        
    from datalake_amplitude_clean_staging_prod."170698_home_page_viewed_events"
    where year = 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
search_results_page_viewed as (
    select 
        min(ts_event) as ts_event, 
        id_amplitude, 
        id_session,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
        
    from datalake_amplitude_clean_staging_prod."170698_search_results_page_viewed_events"
    where year = 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
schedule_page_viewed as (
    select 
        min(ts_event) as ts_event, 
        id_amplitude, 
        id_session,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term
        
    from datalake_amplitude_clean_staging_prod."170698_schedule_page_viewed_events"
    where year = 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8
),
visit_schedule_confirmed as (
    select 
        min(ts_event) as ts_event, 
        id_amplitude, 
        id_session,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_source=', 2), '&', 1), 'direct') as utm_source,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_medium=', 2), '&', 1), 'direct') as utm_medium,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_campaign=', 2), '&', 1), 'direct') as utm_campaign,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_content=', 2), '&', 1), 'direct') as utm_content,
        coalesce(split_part(split_part(json_extract_scalar(user_properties, '$.entrance_uri'), 'utm_term=', 2), '&', 1), 'direct') as utm_term,
        json_extract_scalar(event_properties, '$.visit_code') as visit_code
    from datalake_amplitude_clean_staging_prod."170698_visit_schedule_confirmed_events"
    where year = 2019 and platform = 'Web'
    group by 2,3,4,5,6,7,8,9
),
pre_events as (
    select *, null as visit_code from listing_page_viewed
    union all select *, null as visit_code from home_page_viewed
    union all select *, null as visit_code from search_results_page_viewed
    union all select *, null as visit_code from schedule_page_viewed
    union all select * from visit_schedule_confirmed
),
events_rank as (
    select min(ts_event) as ts_event, id_amplitude, id_session
    from pre_events group by 2,3
),
events as (
    select 
        p.* 
    from pre_events p
    inner join events_rank r
    on p.ts_event=r.ts_event 
       and p.id_amplitude=r.id_amplitude
       and p.id_session=r.id_session
),
conversions as (
	-- retrieve conversion events per amplitude user
	-- conversion def: booking that resulted in a visit with tenant prospect present onsite
	select
	    evt.ts_event,
	    evt.id_amplitude,
	    rank() over (partition by id_amplitude order by ts_event) as rnk_conversion
	from visit_schedule_confirmed evt
	join datalake_clean.ods_dim_visit dv on dv.cd_visit = evt.visit_code
	join datalake_clean.ods_dim_booking db on db.id_visit = dv.id_visit and db.status = 'Realizado' and db.visitor_arrived = '1'
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
			(case when evt.utm_campaign like '%branded%' then 'true'
                  when evt.utm_campaign like '%institucional%' then 'true'
                  else 'false' end)
			as utm_source_medium_branded,
		evt.utm_source,
		evt.utm_medium,
		evt.utm_campaign,
		evt.utm_content,
		evt.utm_term,
		evt.ts_event as session_start_time,
		min(conv.ts_event) as conversion_time,
		min(conv.rnk_conversion) as nst_conversion
	from events evt
	join conversions conv on conv.id_amplitude = evt.id_amplitude and conv.ts_event >= evt.ts_event
	group by 1,2,3,4,5,6,7,8,9,10
    order by 1,11,10
)
-- aggregate touchpoints to unique conversions with their path concatenated in one column
-- conversions July - September 2019
-- lookback window of 6 month
select
	cast(date_format(date(conversion_time), '%Y%m%d') as integer) as sk_conversion_date,
	cast(id_amplitude * 1000 + nst_conversion as bigint) as unique_conversion_id,
	cast(array_join(array_agg(utm_source_medium), '; ') as varchar(20000)) as path_utm_source_medium,
	cast(array_join(array_agg(utm_source_medium_branded), '; ') as varchar(20000)) as path_utm_source_medium_branded,
	cast(array_join(array_agg(utm_source), '; ') as varchar(20000)) as path_utm_source,
	cast(array_join(array_agg(utm_medium), '; ') as varchar(20000)) as path_utm_medium,
	cast(array_join(array_agg(utm_campaign), '; ') as varchar(20000)) as path_utm_campaign,
	cast(array_join(array_agg(utm_content), '; ') as varchar(20000)) as path_utm_content,
	cast(array_join(array_agg(utm_term), '; ') as varchar(20000)) as path_utm_term
from touchpoints
where conversion_time >= date('2019-07-01')
and date_diff('month', session_start_time, conversion_time) <= 6
group by 1, 2;
