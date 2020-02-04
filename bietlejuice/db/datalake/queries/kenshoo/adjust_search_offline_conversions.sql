with amplitude_schedules as (
    select distinct
        ts_event as dt,
        '_k_' || up_gclid || '_k_'  as gclid
    from
        datalake_amplitude_clean_prod.events
    where
        up_gclid is not null
        and up_platform = 'iOS'
        and date(ts_event) = date('{dt}')
)
select
  dt as "Date",
  gclid as "GCLID",
  'booking_sdk_ios' as "Conversion Type",
  1 as "Qty."
from amplitude_schedules
;
