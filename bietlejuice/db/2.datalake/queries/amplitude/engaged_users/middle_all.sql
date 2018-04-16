listings as (
  select
    _year,
    _month,
    _week,
    _day,
    amplitude_id,
    house_id,
    'QuintoAndar' as region,
    'QuintoAndar' as city,
    partial
  from all_events
),
