SELECT
  month_start,
  dr.sk_region,
  ch.country_code,
  COUNT(DISTINCT id_house_listing) AS ongoing_listings
FROM
  datalake_rental_historical_follow_up.house_listings_daily_info AS h
JOIN 
  dw_public.dim_region AS dr
    ON h.id_region = dr.sk_region
JOIN
  datalake_ebdb_country.house AS ch
    ON h.id_house = ch.id_house
JOIN 
  dw_public.dim_date AS d
    ON d.date >= DATE(h.ts_status_started)
    AND d.date < COALESCE(DATE(h.ts_status_ended), CURRENT_DATE())
WHERE
  status_history = 'publicado'
  AND dr.city_group IS NOT NULL
  AND d.date = d.month_end
  AND h.year = d.year
  AND h.month = d.month
  AND h.day = d.day
GROUP BY 1, 2, 3