with amplitude_schedules as (
	select
        et as event_type,
        platform,
        cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as "Date",
        case when u_gclid != '' then '_k_' || u_gclid || '_k_' end as "GCLID"
        -- Appending _k_ so kenshoo client can decode as google client id
	from datalake_clean.amplitude_events evt
	where trim(ym) >= '2019-02'
        and trim(et) = 'visit_schedule_confirmed'
        and u_utm_source = 'google'
        and u_utm_medium = 'cpc'
        group by 1,2,3,4
)
select
    "Date",
     "GCLID",
     '' as "Conversion Type",
      1 as "Qty."
from amplitude_schedules
where date("Date") >= current_date - interval '7' day
    and "GCLID" is not null