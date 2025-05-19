WITH house_status AS (
  SELECT DISTINCT
    id_house,
    status,
    ts_state_started,
    ts_state_ended
  FROM
    datalake_ebdb_listing.lbc_status_version_order
  WHERE
    is_last_state_of_day
)
SELECT
  UUID() AS id,
  CONCAT(dl.id_house, dd.year, dd.month, dd.day) AS business_id,
  dl.id_house AS property_id,
  fdi.sk_region AS location_id,
  IF(fdi.sk_company_supply = -1, '1P', fdi.sk_company_supply) AS company_uuid,
  'RENT' AS business_context,
  SUM(fdi.visits_booked) AS visits_scheduled_count,
  TIMESTAMP(dd.date) AS ts_event,
  dd.year,
  dd.month,
  dd.day
FROM
  dw_rent.fact_house_listing_daily_infos AS fdi
INNER JOIN
  dw_rent.dim_house_listing AS dl
    ON dl.id_house = fdi.sk_house
      AND dl.is_last_version = TRUE
LEFT JOIN
  dw_public.dim_date AS dd
    ON dd.sk_date = fdi.sk_date
INNER JOIN
  house_status AS hs
    ON hs.id_house = dl.id_house
    AND MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE(hs.ts_state_started) AND DATE(hs.ts_state_ended)
WHERE
  MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND hs.status IN ('publicado', 'PUBLISHED')
GROUP BY
  2, 3, 4, 5, 6, 8, 9, 10, 11
HAVING
  visits_scheduled_count > 0
