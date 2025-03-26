SELECT
  UUID() AS id,
  CONCAT(dl.id_house, dd.year, dd.month, dd.day) AS business_id,
  dl.id_house AS property_id,
  fl.sk_region AS location_id,
  IF(di.sk_company_supply = -1, '1P', di.sk_company_supply) AS company_uuid,
  'RENT' AS business_context,
  SUM(di.page_views) AS traffic_count,
  TIMESTAMP(dd.date) AS ts_event,
  dd.year,
  dd.month,
  dd.day
FROM
  dw_rent.fact_house_listing_daily_infos AS di
INNER JOIN
  dw_rent.dim_house_listing AS dl
    ON dl.id_house = di.sk_house
    AND dl.is_last_version = TRUE
INNER JOIN
  dw_rent.fact_house_listings AS fl
    ON fl.sk_house_listing = dl.sk_house_listing
LEFT JOIN
  dw_public.dim_date AS dd
    ON dd.sk_date = di.sk_date
WHERE
  MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND dl.status IN ('publicado', 'PUBLISHED')
GROUP BY
  2, 3, 4, 5, 6, 8, 9, 10, 11
HAVING
  traffic_count > 0
