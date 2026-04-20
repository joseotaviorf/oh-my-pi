WITH base_listings AS (
  SELECT
    listings.dejavuid,
    region_neighborhood.id AS neighborhood_id,
    region_city.id AS city_id,
    compounds.address.street,
    compounds.address.neighborhood,
    compounds.address.city,
    compounds.address.state_code,
    state_dim.name AS state,
    compounds.address.country_code,
    country_dim.name AS country,
    compounds.lat,
    compounds.lng,
    MAX(
      CASE
        WHEN listings.business_context = 'RENT'
          AND listings.source_name = 'ebdb_houses'
          THEN 1
        ELSE 0
      END
    ) AS is_rent,
    MAX(
      CASE
        WHEN listings.business_context = 'SALE'
          AND listings.source_name = 'ebdb_houses'
          THEN 1
        ELSE 0
      END
    ) AS is_sale,
    MAX(
      CASE
        WHEN listings.business_context = 'RENT'
          AND listings.source_name = 'navent_houses'
          THEN 1
        ELSE 0
      END
    ) AS is_navent_rent,
    MAX(
      CASE
        WHEN listings.business_context = 'SALE'
          AND listings.source_name = 'navent_houses'
          THEN 1
        ELSE 0
      END
    ) AS is_navent_sale
  FROM
    vespucio_prod_delta.listings AS listings
  INNER JOIN
    vespucio_prod_delta.house_compounds AS compounds
      ON listings.dejavuid = compounds.dejavuid
  INNER JOIN
    datalake_ebdb_clean.state AS state_dim
      ON state_dim.abbreviation = compounds.address.state_code
  INNER JOIN
    datalake_ebdb_clean.region AS region_city
      ON LOWER(region_city.name) = LOWER(compounds.address.city)
      AND region_city.id_state = state_dim.id
  LEFT JOIN
    datalake_ebdb_clean.region AS region_sub
      ON region_sub.id_parent_region = region_city.id
  LEFT JOIN
    datalake_ebdb_clean.region AS region_neighborhood
      ON LOWER(region_neighborhood.name) = LOWER(compounds.address.neighborhood)
      AND (
        region_neighborhood.id_parent_region = region_city.id
        OR region_neighborhood.id_parent_region = region_sub.id
      )
  INNER JOIN
    datalake_ebdb_clean.country AS country_dim
      ON country_dim.id = state_dim.id_country
  WHERE
    (listings.source_name = 'ebdb_houses' OR listings.source_name = 'navent_houses')
    AND compounds.address.country_code = 'BR'
    AND listings.status = 'PUBLISHED'
    AND listings.business_context IN ('RENT', 'SALE')
  GROUP BY
    listings.dejavuid,
    region_neighborhood.id,
    region_city.id,
    compounds.address.street,
    compounds.address.neighborhood,
    compounds.address.city,
    compounds.address.state_code,
    state_dim.name,
    compounds.address.country_code,
    country_dim.name,
    compounds.lat,
    compounds.lng
)

SELECT
  neighborhood_id,
  city_id,
  street,
  neighborhood,
  city,
  state_code,
  state,
  country_code,
  country,
  SUM(is_rent) AS count_rent,
  SUM(is_sale) AS count_sale,
  SUM(is_navent_rent) AS navent_count_rent,
  SUM(is_navent_sale) AS navent_count_sale,
  AVG(lat) AS centroid_lat,
  AVG(lng) AS centroid_lng,
  FILTER(ARRAY(
    CASE WHEN SUM(is_rent + is_navent_rent) > 0 THEN 'RENT' END,
    CASE WHEN SUM(is_sale + is_navent_sale) > 0 THEN 'SALE' END
  ), x -> x IS NOT NULL) AS business_contexts
FROM
  base_listings
GROUP BY GROUPING SETS (
  (neighborhood_id, city_id, street, neighborhood, city, state_code, state, country_code, country),
  (neighborhood_id, city_id, neighborhood, city, state_code, state, country_code, country),
  (city_id, city, state_code, state, country_code, country)
)
