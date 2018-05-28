listings as (
  select
    _year,
    _month,
    _week,
    _day,
    uuid,
    'QuintoAndar' as region,
    'QuintoAndar' as city,
    partial
  from all_events
)
