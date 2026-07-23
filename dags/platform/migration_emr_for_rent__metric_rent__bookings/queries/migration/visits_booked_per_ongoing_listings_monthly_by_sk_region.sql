WITH ongoing_listings AS (
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
    status_history IN ('publicado', 'PUBLISHED')
    AND dr.city_group IS NOT NULL
    AND d.date = d.month_end
    AND h.year = d.year
    AND h.month = d.month
    AND h.day = d.day
  GROUP BY 1, 2, 3
),

visits_booked AS (
  SELECT
    dd.month_start,
    dr.sk_region,
    rf.country_code,
    COUNT(DISTINCT CASE WHEN (rf.sk_booking_created_date  > 0) THEN rf.sk_booking ELSE NULL END) AS visits_booked
  FROM
    dw_rent.fact_listing_rent_flows AS rf
  JOIN
    dw_public.dim_date AS dd
      on dd.sk_date = rf.sk_booking_created_date
  JOIN
    dw_public.dim_region AS dr
      on dr.sk_region = rf.sk_region
  WHERE
    dr.city_group IS NOT NULL
    AND dd.date < CURRENT_DATE()
  GROUP BY 1, 2, 3
)

SELECT
  vb.month_start,
  vb.sk_region,
  vb.country_code,
  vb.visits_booked/ol.ongoing_listings AS visits_booked_per_ongoing_listings
FROM
  visits_booked AS vb
LEFT JOIN
  ongoing_listings AS ol
    ON ol.month_start = vb.month_start
    AND vb.sk_region = ol.sk_region
    AND vb.country_code = ol.country_code
WHERE
  vb.month_start < DATE_TRUNC('month', CURRENT_DATE())
