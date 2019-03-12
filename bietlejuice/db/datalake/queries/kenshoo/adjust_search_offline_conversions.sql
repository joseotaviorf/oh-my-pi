with amplitude_schedules as (
  select
	cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as dt,
	'_k_' || u_gclid || '_k_' as gclid
  from datalake_clean.amplitude_events evt
  where ym >= '2019-02'
    and et = 'visit_schedule_confirmed'
	and trim(app) = '170698'
	and trim(u_gclid) != ''
	and platform = 'iOS'
  group by 1, 2
)
select
  dt as "Date",
  gclid as "GCLID",
  'booking_sdk_ios' as "Conversion Type",
  1 as "Qty."
from amplitude_schedules
where date(dt) >= current_date - interval '7' day
order by 1 desc
;