count_houses_prev as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    partial,
    amplitude_id,
    dense_rank() over (partition by _year, _month, _week, _day, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, _month, _week, _day, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_daily,
    dense_rank() over (partition by _year, _month, _week, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, _month, _week, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_weekly,
    dense_rank() over (partition by _year, _month, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, _month, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_monthly,
    dense_rank() over (partition by _year, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_yearly
  from listings
)
select
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  sum(house_id_count_daily) as daily_count,
  sum(house_id_count_weekly) as weekly_count,
  sum(house_id_count_monthly) as monthly_count,
  sum(house_id_count_yearly) as yearly_count
from count_houses_prev
group by 1, 2, 3, 4, 5, 6, 7
;