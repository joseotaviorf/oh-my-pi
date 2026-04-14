WITH base_listings AS (
  SELECT
    l.dejavuid,
    h.address.street,
    h.address.neighborhood,
    h.address.city,
    r.id AS city_id,
    h.address.state_code,
    s.name AS state,
    h.address.country_code,
    co.name AS country,
    h.lat,
    h.lng,
    MAX(CASE WHEN l.business_context = 'RENT' AND l.source_name = 'ebdb_houses' THEN 1 ELSE 0 END) AS is_rent,
    MAX(CASE WHEN l.business_context = 'SALE' AND l.source_name = 'ebdb_houses' THEN 1 ELSE 0 END) AS is_sale,
    MAX(CASE WHEN l.business_context = 'RENT' AND l.source_name = 'navent_houses' THEN 1 ELSE 0 END) AS is_navent_rent,
    MAX(CASE WHEN l.business_context = 'SALE' AND l.source_name = 'navent_houses' THEN 1 ELSE 0 END) AS is_navent_sale
  FROM vespucio_prod_delta.listings l
  INNER JOIN vespucio_prod_delta.house_compounds h ON l.dejavuid = h.dejavuid
  INNER JOIN datalake_ebdb_clean.state s ON s.abbreviation = h.address.state_code
  INNER JOIN datalake_ebdb_clean.region r ON lower(r.name) = lower(h.address.city) AND r.id_state = s.id
  INNER JOIN datalake_ebdb_clean.country co ON co.id = s.id_country
  WHERE l.source_name = 'ebdb_houses' OR l.source_name = 'navent_houses'
    AND h.address.country_code = 'BR'
    AND l.status = 'PUBLISHED'
    AND l.business_context IN ('RENT', 'SALE')
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
)

SELECT
  street,
  neighborhood,
  city,
  city_id,
  state_code,
  state,
  country_code,
  country,
  SUM(is_rent) AS count_rent,
  SUM(is_sale) AS count_sale,
  SUM(is_navent_rent) AS navent_count_rent,
  SUM(is_navent_sale) AS navent_count_sale,
  filter(array(
    CASE WHEN SUM(is_rent + is_navent_rent) > 0 THEN 'RENT' END,
    CASE WHEN SUM(is_sale + is_navent_sale) > 0 THEN 'SALE' END
  ), x -> x IS NOT NULL) AS business_contexts,
  AVG(lat) AS centroid_lat,
  AVG(lng) AS centroid_lng
FROM base_listings
GROUP BY GROUPING SETS (
  (street, neighborhood, city, city_id, state_code, state, country_code, country),
  (neighborhood, city, city_id, state_code, state, country_code, country),
  (city, city_id, state_code, state, country_code, country)
)
