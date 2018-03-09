select distinct
  _year,
  _month,
  _week,
  _day,
  partial,
  dense_rank() over (partition by _year, _month, _week, _day  order by amplitude_id asc)
    + dense_rank() over (partition by _year, _month, _week, _day order by amplitude_id desc)
    - 1 as daily_count,
  dense_rank() over (partition by _year, _week order by amplitude_id asc)
    + dense_rank() over (partition by _year, _week order by amplitude_id desc)
    - 1 as weekly_count,
  dense_rank() over (partition by _year, _month order by amplitude_id asc)
    + dense_rank() over (partition by _year, _month order by amplitude_id desc)
    - 1 as monthly_count,
  dense_rank() over (partition by _year order by amplitude_id asc)
    + dense_rank() over (partition by _year order by amplitude_id desc)
    - 1 as yearly_count
from all_events
;