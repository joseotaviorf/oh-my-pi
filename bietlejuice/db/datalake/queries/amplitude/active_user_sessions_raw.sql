with sessions_raw as (
    select
	    id_amplitude,
	    date(ts_event) as event_date,
	    id_session,
        coalesce(cast(json_extract(user_properties, '$.utm_source') as varchar), '') as u_utm_source,
        coalesce(cast(json_extract(user_properties, '$.utm_medium') as varchar), '') as u_utm_medium,
        coalesce(cast(json_extract(user_properties, '$.utm_campaign') as varchar), '') as u_utm_campaign,
        coalesce(cast(json_extract(user_properties, '$.utm_content') as varchar), '') as u_utm_content,
        coalesce(cast(json_extract(user_properties, '$.utm_term') as varchar), '') as u_utm_term,
	    country,
	    city,
	    region,
        coalesce(cast(json_extract(user_properties, '$.platform') as varchar), '') as u_platform,
	    id_app,
	    event_type,
	    min(ts_event) as session_start_ts,
	    date(ts_server_uploaded) as server_upload_time
    from datalake_amplitude_clean_prod.events
    where ym >= '{ym}'
    and date(ts_server_uploaded) = date('{dt}')
    and id_session != -1
    and (id_app = '170698' or id_app ='183047')
    group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,16
),
rn as (
	select
		*,
		row_number() over (partition by event_date, id_amplitude, session_start_ts) as rn
	from sessions_raw
)
select
    cast(event_date as varchar) as event_date,
    cast(server_upload_time as varchar) as server_upload_time,
    cast(session_start_ts as varchar) as session_start_ts,
    id_amplitude,
    id_session,
    country,
    city,
    region,
    u_platform as platform,
    u_utm_source as utm_source,
    u_utm_medium as utm_medium,
    u_utm_campaign as utm_campaign,
    u_utm_content as utm_content,
    u_utm_term as utm_term,
    event_type,
    id_app as app
from rn
    where rn = 1