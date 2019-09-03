with amplitude_schedules as (
    select
        cast(regexp_extract(event_time, '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp) as "Date",
        case when user_gclid is not null then '_k_' || user_gclid || '_k_' end as "GCLID"
        -- Appending _k_ so kenshoo client can decode as google client id
    from
        datalake_amplitude_clean_prod.visit_schedule_confirmed_events
    where year >= 2019
        and user_utm_source = 'google'
        and user_utm_medium = 'cpc'
        and date(cast(regexp_extract(event_time,
            '(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})', 1) as timestamp)) = date('{dt}')
)
select
    "Date",
     "GCLID",
     'visit_schedule_confirmed_amp' as "Conversion Type",
      1 as "Qty."
from amplitude_schedules
where "GCLID" is not null
