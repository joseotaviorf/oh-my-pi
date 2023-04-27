SELECT
  MAKE_DATE(year, month, day) AS day,
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
WHERE
  status_history = 'publicado'
  AND dr.city_group IS NOT NULL
GROUP BY 1, 2