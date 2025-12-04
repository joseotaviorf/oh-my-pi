SELECT
  h.address.street,
  h.address.neighborhood,
  h.address.city,
  c.id as city_id,
  collect_set(l.business_context) as business_contexts,
  s.name as state,
  h.address.state_code,
  h.address.country_code as country_code,
  CASE
    WHEN GROUPING(h.address.street) = 0 THEN 'street'
    WHEN GROUPING(h.address.neighborhood) = 0 THEN 'neighborhood'
    WHEN GROUPING(h.address.city) = 0 THEN 'city'
    ELSE 'global'
  END AS region_level,
  AVG(h.lat) AS centroid_lat,
  AVG(h.lng) AS centroid_lng
FROM
  vespucio_prod_delta.listings l
INNER JOIN
  vespucio_prod_delta.house_compounds h ON l.dejavuid = h.dejavuid
INNER JOIN
  datalake_ebdb_clean.state s ON s.abbreviation = h.address.state_code
INNER JOIN
  datalake_ebdb_clean.city c ON lower(c.name) = lower(h.address.city) AND c.uf = s.abbreviation
WHERE
  l.source_name = "ebdb_houses" AND h.address.country_code = "BR"
GROUP BY GROUPING SETS (
    (h.address.street, h.address.neighborhood, h.address.city, c.id, h.address.state_code, s.name, country_code),
    (h.address.neighborhood, h.address.city, c.id, h.address.state_code, s.name, country_code),
    (h.address.city, c.id, h.address.state_code, s.name, country_code)
)
