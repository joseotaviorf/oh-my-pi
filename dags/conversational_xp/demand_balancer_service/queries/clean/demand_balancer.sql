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
where MAKE_DATE(year, month, day) = MAKE_DATE({year}, {month}, {day})