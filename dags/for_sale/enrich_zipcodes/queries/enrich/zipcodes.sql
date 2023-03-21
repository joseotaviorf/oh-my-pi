/* CTE that filters dw_public.region to contain only subregions, and regions linked to the cities that we have in ITBI. */
WITH regions AS (
  SELECT
      r.id AS id_region,
      r.name,
      r.city_name,
      ST_GeomFromWKT(p.polygon) AS polygon
  FROM
      datalake_region.region AS r
  LEFT JOIN
      datalake_ebdb_clean.polygon_region AS p
          ON p.id_region = r.id
  WHERE
      r.city_group IN ('RMSP', 'Belo Horizonte')
      AND r.city_name IN ('São Paulo', 'Belo Horizonte')
      AND r.level = 'SubRegiao'
      AND p.polygon IS NOT NULL
),
/* CTE that retrieves all the zip codes already registered at QuintoAndar */
quintoandar_zipcodes AS (
  SELECT
      h.id AS id_house,
      h.id_region,
      h.zipcode,
      h.address,
      h.number
  FROM
      datalake_ebdb_listing.house AS h
  JOIN
      datalake_ebdb_listing.house_listing AS hl
          ON hl.id_house = h.id
  WHERE
      h.id_region IS NOT NULL
      AND h.zipcode IS NOT NULL
      AND LENGTH(zipcode) = 9 
      AND CAST(h.zipcode AS BIGINT) IS NULL
      AND (LENGTH(h.zipcode) - LENGTH(REPLACE(h.zipcode, '-', ''))) = 1
      AND h.zipcode NOT IN ('0', '00000-000', '00000-001')
),
/* CTEs that try to handle zip codes that have more than one address. Thus, picking the address with the highest probability of being the correct one. */
metrics_aux AS (
  SELECT
      zipcode,
      name,
      city_name,
      id_region,
      LAST(address) AS address,
      COUNT(DISTINCT id_house) AS listings_by_zipcode,
      COUNT(DISTINCT TRANSLATE(LOWER(address),'áãàâäåéêèëíîìïóõôöúüùûç', 'aaaaaaeeeeiiiioooouuuuc')) AS streets_by_zipcode,
      COUNT(DISTINCT TRANSLATE(LOWER(address),'áãàâäåéêèëíîìïóõôöúüùûç', 'aaaaaaeeeeiiiioooouuuuc')||number) AS buildings_by_zipcode
  FROM
      quintoandar_zipcodes
  LEFT JOIN
      regions
          USING(id_region)
  WHERE
      name IS NOT NULL
  GROUP BY
      1, 2, 3, 4
),
metrics AS (
  SELECT
    zipcode,
    name,
    city_name,
    address,
    id_region,
    listings_by_zipcode,
    streets_by_zipcode,
    buildings_by_zipcode,
    SIZE(COLLECT_SET(name) OVER (PARTITION BY zipcode)) AS neighborhoods_by_zipcode,
    ROW_NUMBER() OVER (PARTITION BY zipcode ORDER BY listings_by_zipcode DESC) AS ranking_by_neighborhood
  FROM
    metrics_aux
),
discard_rules AS (
  SELECT
    zipcode,
    name,
    city_name,
    id_region,
    address,
    listings_by_zipcode,
    streets_by_zipcode,
    buildings_by_zipcode,
    neighborhoods_by_zipcode,
    ranking_by_neighborhood,
    CASE
        WHEN neighborhoods_by_zipcode > 3 THEN 'DISCARD'
        WHEN neighborhoods_by_zipcode > 1 AND listings_by_zipcode = 1 THEN 'DISCARD'
        WHEN neighborhoods_by_zipcode > 1 AND ranking_by_neighborhood > 1 THEN 'DISCARD'
        ELSE NULL
    END AS check
  FROM
    metrics
),
depara_neighborhoods AS (
  SELECT
      id_region,
      name,
      city_name,
      zipcode,
      address
  FROM
      discard_rules
  WHERE
      check IS NULL
),
/* CTE with the zip codes of the City of São Paulo, retrieved by open API */
sao_paulo_ceps_api AS (
  SELECT
      c.zipcode,
      c.address,
      c.neighborhood,
      'São Paulo' AS city_name,
      r.id_region,
      IF(c.lat IS NOT NULL AND c.lng IS NOT NULL, ST_Point(c.lng, c.lat), NULL) AS points,
      CASE
          WHEN c.neighborhood = r.name THEN r.name
          ELSE NULL
      END AS neighborhood_quintoandar_match
  FROM
      datalake_gsheets_clean.zipcodes_sp AS c
  LEFT JOIN
      regions AS r
          ON c.neighborhood = r.name
          AND r.city_name = 'São Paulo'
  GROUP BY
      1, 2, 3, 4, 5, 6, 7
),
regions_normalization AS (
    SELECT
        COALESCE(d.zipcode, c.zipcode) AS zipcode,
        COALESCE(d.city_name, c.city_name) AS city_name,
        COALESCE(d.id_region, c.id_region, r.id_region, -1) AS id_region,
        COALESCE(d.name, c.neighborhood_quintoandar_match, r.name, c.neighborhood) AS neighborhood,
        COALESCE(d.address, ARRAY_JOIN(TRANSFORM(SPLIT(c.address, ' '), x -> IF(CAST(x AS BIGINT) IS NOT NULL, '', x)), ' ')) AS address
    FROM
        sao_paulo_ceps_api AS c
    FULL OUTER JOIN
        depara_neighborhoods AS d
            ON c.zipcode = d.zipcode
    LEFT JOIN
        regions AS r
            ON c.points IS NOT NULL
            AND ST_Within(c.points, r.polygon) = TRUE
    GROUP BY 
    1, 2, 3, 4, 5
)
SELECT
    zipcode,
    id_region,
    city_name,
    neighborhood,
    address
FROM
    regions_normalization
WHERE
    address IS NOT NULL
