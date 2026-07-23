WITH first_bookings AS (
  SELECT
    sk_client,
    country_code,
    month
  FROM (
    SELECT
      rf.sk_client,
      rf.country_code,
      DATE_TRUNC('MONTH', dd.date) AS month,
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
  month,
  country_code,
  COUNT(DISTINCT fb.sk_client) AS new_bookers
FROM first_bookings AS fb
WHERE
  month < DATE_TRUNC('MONTH', CURRENT_DATE)
GROUP BY
  1,
  2
