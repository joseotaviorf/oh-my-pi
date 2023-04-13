SELECT
  business_type,
  city_group,
  guarantee,
  halfyear,
  listing_category_start,
  quarter,
  rent_flow_origin,
  rental_administrator,
  tier,
  visits_booked,
  visits_completed,
  offers_submitted,
  offers_accepted,
  evaluation_started,
  evaluation_positive,
  documentation_sent,
  credit_approved,
  contracts_signed,
  dt_event,  
  dt_week_started,
  year,
  month,
  day,
  country_code,
  NOW() AS ts_load
FROM 
  datalake_metric_rent_demand_event.metric_rent_demand_event
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY year,month,day ORDER BY ts_updated DESC) = 1


