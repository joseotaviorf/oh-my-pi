WITH ongoing_listings AS (
  SELECT
    MAKE_DATE(year, month, day) AS date,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
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
    status_history IN ('publicado', 'PUBLISHED')
    AND dr.city_group IS NOT NULL
  GROUP BY 1, 2
),

visits_booked AS (
  SELECT
    dd.date,
    rf.country_code,
    COUNT(DISTINCT CASE WHEN (rf.sk_booking_created_date  > 0) THEN rf.sk_booking ELSE NULL END) AS visits_booked
  FROM
    dw_rent.fact_listing_rent_flows AS rf
  JOIN
    dw_public.dim_date AS dd
      ON dd.sk_date = rf.sk_booking_created_date
  JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = rf.sk_region
  WHERE
    dr.city_group IS NOT NULL
    AND dd.date < CURRENT_DATE()
  GROUP BY 1, 2
)

SELECT
  vb.date AS day,
  vb.country_code,
  vb.visits_booked/ol.ongoing_listings AS visits_booked_per_ongoing_listings
FROM
  visits_booked AS vb
LEFT JOIN
  ongoing_listings AS ol
    ON ol.date = vb.date
    AND vb.country_code = ol.country_code
WHERE
  vb.date IS NOT NULL
