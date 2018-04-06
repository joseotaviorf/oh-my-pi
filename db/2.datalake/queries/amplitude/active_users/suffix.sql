cte_day as (
  select
    _year,
    _month,
    _week,
    _day,
    partial,
    approx_distinct(amplitude_id) as daily_count
  from all_events
  group by _year, _month, _week, _day, partial
),
cte_week as (
  select
    _year,
    _week,
    partial,
    approx_distinct(amplitude_id) as weekly_count
  from all_events
  group by _year, _week, partial
),
cte_month as (
  select
    _year,
    _month,
    partial,
    approx_distinct(amplitude_id) as monthly_count
  from all_events
  group by _year, _month, partial
),
cte_year as (
  select
    _year,
    partial,
    approx_distinct(amplitude_id) as yearly_count
  from all_events
  group by _year, partial
)
select
  ay._year,
  am._month,
  aw._week,
  ad._day,
  'QuintoAndar' as region,
  'QuintoAndar' as city,
  ad.partial,
  ad.daily_count,
  aw.weekly_count,
  am.monthly_count,
  ay.yearly_count
from cte_day ad
join cte_week aw
  on ad._year = aw._year
    and ad._week = aw._week
join cte_month am
  on ad._year = am._year
    and ad._month = am._month
join cte_year ay
  on ad._year = am._year
;