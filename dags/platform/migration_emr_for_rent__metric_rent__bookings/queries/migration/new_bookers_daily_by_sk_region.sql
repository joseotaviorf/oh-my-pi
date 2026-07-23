WITH first_bookings AS (
  SELECT
    sk_client,
    sk_region,
    country_code,
    first_booking_created_date
  FROM (
    SELECT
      rf.sk_client,
      rf.sk_region,
      rf.country_code,
      DATE_TRUNC('DAY', dd.date) AS first_booking_created_date,
      ROW_NUMBER() OVER (PARTITION BY rf.sk_client ORDER BY dd.date) AS _w,
      dd.date
    FROM dw_rent.fact_listing_rent_flows AS rf
    JOIN dw_public.dim_date AS dd
      ON dd.sk_date = rf.sk_booking_created_date
    WHERE
      rf.sk_booking_created_date > 0
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  first_booking_created_date,
  fb.sk_region,
  country_code,
  COUNT(DISTINCT fb.sk_client) AS new_bookers
FROM first_bookings AS fb
GROUP BY
  1,
  2,
  3
