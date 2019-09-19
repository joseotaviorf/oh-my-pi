with amplitude_schedules as (
  select
        distinct
        cast(regexp_extract(event_time, '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp) as dt,
        '_k_' || user_gclid || '_k_'  as gclid
  from
        datalake_amplitude_clean_prod.visit_schedule_confirmed_events
  where app = 170698
        and user_gclid is not null
        and platform = 'iOS'
        and date(cast(regexp_extract(event_time,
            '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp)) = date('{dt}')
)
select
  dt as "Date",
  gclid as "GCLID",
  'booking_sdk_ios' as "Conversion Type",
  1 as "Qty."
from amplitude_schedules
;
