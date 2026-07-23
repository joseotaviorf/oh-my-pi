SELECT
    dd.date AS day,
    rf.country_code,
    COUNT(DISTINCT rf.sk_client) AS bookers
FROM
  dw_rent.fact_listing_rent_flows AS rf
JOIN
  dw_public.dim_date AS dd
    ON rf.sk_booking_created_date = dd.sk_date
WHERE
  rf.sk_booking_created_date > -1
GROUP BY 1,2
