select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  dense_rank() over (partition by _year, _month, _week, _day, region, city, partial order by amplitude_id asc)
    + dense_rank() over (partition by _year, _month, _week, _day, region, city, partial order by amplitude_id desc)
    - 1 as daily_count,
  dense_rank() over (partition by _year, _month, _week, region, city, partial order by amplitude_id asc)
    + dense_rank() over (partition by _year, _month, _week, region, city, partial order by amplitude_id desc)
    - 1 as weekly_count,
  dense_rank() over (partition by _year, _month, region, city, partial order by amplitude_id asc)
    + dense_rank() over (partition by _year, _month, region, city, partial order by amplitude_id desc)
    - 1 as monthly_count,
  dense_rank() over (partition by _year, region, city, partial order by amplitude_id asc)
    + dense_rank() over (partition by _year, region, city, partial order by amplitude_id desc)
    - 1 as yearly_count
from all_events
;