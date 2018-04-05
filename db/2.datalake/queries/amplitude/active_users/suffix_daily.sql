select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  approx_distinct(amplitude_id) over (partition by _year, _month, _week, _day) as daily_count
from all_events
;