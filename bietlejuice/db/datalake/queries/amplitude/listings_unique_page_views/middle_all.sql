listings as (
  select
    _year,
    _month,
    _week,
    _day,
    'QuintoAndar' as region,
    'QuintoAndar' as city,
    partial,
    house_id
  from all_events
)
