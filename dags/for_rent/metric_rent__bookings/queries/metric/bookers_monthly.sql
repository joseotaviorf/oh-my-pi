SELECT
    DATE_TRUNC('month', dd.date) AS month,
    rf.country_code,
    COUNT(DISTINCT rf.sk_client) AS bookers
FROM 
  dw_public.fact_listing_rent_flows AS rf
JOIN 
  dw_public.dim_date AS dd
    ON rf.sk_booking_created_date = dd.sk_date
GROUP BY 1,2