SELECT
  halfyear,
  quarter,
  business_type,
  city_group,
  guarantee,
  listing_category_start,
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
  country_code,
  NOW() AS ts_load
FROM 
  dw_rent_snapshot.rent_demand_events_snapshot
WHERE
  year = YEAR(NOW())
  AND month = MONTH(NOW())
  AND day = DAY(NOW())