with amplitude_schedules as (
  select
        distinct
        cast(regexp_extract(trim(evt.event_time), '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp) as dt,
        '_k_' || u_gclid || '_k_' as gclid
  from
        datalake_clean.amplitude_events evt
  where ym >= '2019-02'
        and et = 'visit_schedule_confirmed'
        and trim(app) = '170698'
        and trim(u_gclid) != ''
        and platform = 'iOS'
        and date(cast(regexp_extract(event_time,
            '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp)) >= date('{dt}')
  union
  select
        distinct
        cast(regexp_extract(event_time, '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp) as dt,
        '_k_' || user_gclid || '_k_'  as gclid
  from
        datalake_clean_spark.amplitude_visit_schedule_confirmed_events
  where year >= 2019
        and app = 170698
        and user_gclid is not null
        and platform = 'iOS'
        and date(cast(regexp_extract(event_time,
            '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp)) >= date('{dt}')
)
select
  dt as "Date",
  gclid as "GCLID",
  'booking_sdk_ios' as "Conversion Type",
  1 as "Qty."
from amplitude_schedules
;