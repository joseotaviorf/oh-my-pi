select
  id_house,
  timestamp_available,
  prediction,
  model_version,
  year,
  month,
  day
from
  datalake_demand_balancer_service_raw.demand_balancer
where MAKE_DATE(year, month, day) = DATE_ADD(MAKE_DATE({year}, {month}, {day}), 1)