select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  approx_distinct(amplitude_id) over (partition by _year, _month, _week, _day) as daily_count,
  approx_distinct(amplitude_id) over (partition by _year, _week) as weekly_count,
  approx_distinct(amplitude_id) over (partition by _year, _month) as monthly_count,
  approx_distinct(amplitude_id) over (partition by _year) as yearly_count
from all_events
;