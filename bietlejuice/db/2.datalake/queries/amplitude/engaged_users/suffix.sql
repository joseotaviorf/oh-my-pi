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
    dense_rank() over (partition by _year, _week, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, _month, _week, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_weekly,
    dense_rank() over (partition by _year, _month, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, _month, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_monthly,
    dense_rank() over (partition by _year, amplitude_id, region, city, partial order by house_id asc)
        + dense_rank() over (partition by _year, amplitude_id, region, city, partial order by house_id desc)
        - 1 as house_id_count_yearly
  from listings
),
group_count_houses_daily as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    amplitude_id,
    city,
    region,
    partial
  from count_houses_prev
  group by _year, _month, _week, _day, amplitude_id, city, region, partial
  having sum(house_id_count_daily) >= 3
),
group_count_houses_weekly as (
  select distinct
    _year,
    _month,
    _week,
    amplitude_id,
    city,
    region,
    partial
  from count_houses_prev
  group by _year, _month, _week, amplitude_id, city, region, partial
  having sum(house_id_count_weekly) >= 3
),
group_count_houses_monthly as (
  select distinct
    _year,
    _month,
    amplitude_id,
    city,
    region,
    partial
  from count_houses_prev
  group by _year, _month, amplitude_id, city, region, partial
  having sum(house_id_count_monthly) >= 3
),
group_count_houses_yearly as (
  select distinct
    _year,
    amplitude_id,
    city,
    region,
    partial
  from count_houses_prev
  group by _year, amplitude_id, city, region, partial
  having sum(house_id_count_yearly) >= 3
),
count_houses_daily as (
  select
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    partial,
    count(distinct amplitude_id) as daily_count
  from group_count_houses_daily
  group by _year, _month, _week, _day, region, city, partial
),
count_houses_weekly as (
  select
    _year,
    _month,
    _week,
    region,
    city,
    partial,
    count(distinct amplitude_id) as weekly_count
  from group_count_houses_weekly
  group by _year, _month, _week, region, city, partial
),
count_houses_monthly as (
  select
    _year,
    _month,
    region,
    city,
    partial,
    count(distinct amplitude_id) as monthly_count
  from group_count_houses_monthly
  group by _year, _month, region, city, partial
),
count_houses_yearly as (
  select
    _year,
    region,
    city,
    partial,
    count(distinct amplitude_id) as yearly_count
  from group_count_houses_yearly
  group by _year, region, city, partial
)
select
  d._year,
  d._month,
  d._week,
  d._day,
  d.region,
  d.city,
  d.partial,
  d.daily_count,
  w.weekly_count,
  m.monthly_count,
  y.yearly_count
from count_houses_daily d
join count_houses_weekly w
  on d._year = w._year
    and d._month = w._month
    and d._week = w._week
    and d.region = w.region
    and d.city = w.city
join count_houses_monthly m
  on d._year = m._year
    and d._month = m._month
    and d.region = m.region
    and d.city = m.city
join count_houses_yearly y
  on d._year = y._year
    and d.region = y.region
    and d.city = y.city
;