WITH first_bookings AS (
  SELECT
    rf.sk_client,
    rf.country_code,
    DATE_TRUNC('day', db.dt_created) AS day
  FROM 
    dw_public.fact_listing_rent_flows AS rf
  JOIN 
    dw_public.dim_booking AS db
      ON db.sk_booking = rf.sk_booking
  WHERE 
    rf.sk_booking_created_date > 0
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rf.sk_client ORDER BY db.dt_created) = 1
)

SELECT
  day,
  country_code,
  COUNT(DISTINCT fb.sk_client) AS new_bookers
FROM 
  first_bookings AS fb
GROUP BY 1, 2