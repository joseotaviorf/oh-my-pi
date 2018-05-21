select distinct
  _year,
  _month,
  _week,
  _day,
  region,
  city,
  partial,
  count(uuid) over (partition by _year, _month, _week, _day, region, city, partial) as _daily,
  count(uuid) over (partition by _year, _month, _week, region, city, partial) as _weekly,
  count(uuid) over (partition by _year, _month, region, city, partial) as _monthly,
  count(uuid) over (partition by _year, region, city, partial) as _yearly
from listings
;