with sessions_raw as (
    select
	    amplitude_id,
	    date(cast(regexp_extract(trim(event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp)) as event_date,
	    session_id,
	    u_utm_source,
	    u_utm_medium,
	    u_utm_campaign,
	    u_utm_content,
	    u_utm_term,
	    country,
	    city,
	    region,
	    u_platform,
	    app,
	    min(cast(regexp_extract(trim(event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp)) as session_start_ts
    from datalake_clean.amplitude_events
    where ym >= '2018-01'
    and session_id != '-1'
    and (app = '170698' or app ='183047')
    group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
rn as (
	select
		*,
		row_number() over (partition by event_date, amplitude_id, session_start_ts) as rn
	from sessions_raw
)
select
    event_date,
    session_start_ts,
    amplitude_id,
    session_id,
    country,
    city,
    region,
    u_platform as platform,
    u_utm_source as utm_source,
    u_utm_medium as utm_medium,
    u_utm_campaign as utm_campaign,
    u_utm_content as utm_content,
    u_utm_term as utm_term,
    app as app
from rn
    where rn = 1