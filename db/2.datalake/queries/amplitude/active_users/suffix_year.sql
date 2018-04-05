select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  approx_distinct(amplitude_id) over (partition by _year) as yearly_count
from all_events
;