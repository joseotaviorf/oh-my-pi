SELECT
  h.address.street as street,
  h.address.neighborhood as neighborhood,
  h.address.city as city,
  r.id as city_id,
  collect_set(l.business_context) as business_contexts,
  s.name as state,
  h.address.state_code as state_code,
  h.address.country_code as country_code,
  co.name as country,
  AVG(h.lat) AS centroid_lat,
  AVG(h.lng) AS centroid_lng
FROM
  vespucio_prod_delta.listings l
INNER JOIN
  vespucio_prod_delta.house_compounds h ON l.dejavuid = h.dejavuid
INNER JOIN
  datalake_ebdb_clean.state s ON s.abbreviation = h.address.state_code
INNER JOIN
  datalake_ebdb_clean.region r ON lower(r.name) = lower(h.address.city) AND r.id_state = s.id
INNER JOIN
  datalake_ebdb_clean.country co ON co.id = s.id_country
WHERE
  l.source_name = "ebdb_houses" AND h.address.country_code = "BR" AND l.status = "PUBLISHED"
GROUP BY GROUPING SETS (
    (street, neighborhood, city, city_id, state_code, state, country_code, country),
    (neighborhood, city, city_id, state_code, state, country_code, country),
    (city, city_id, state_code, state, country_code, country)
)
