WITH similar_houses AS (
  SELECT
    ref.id_house,
    sim.id_house AS similar_id_house,
    ref.condo AS reference_condo,
    sim.condo AS similar_condo,
    ref.iptu AS reference_iptu,
    sim.iptu AS similar_iptu,
    6371 * 2 * ASIN(
                SQRT(
                  POWER(SIN(RADIANS(sim.lat - ref.lat)/2),2) +
                  COS(RADIANS(ref.lat)) * COS(RADIANS(sim.lat)) *
                  POWER(SIN(RADIANS(sim.lng - ref.lng) / 2), 2)
                )
    ) AS distance_km,
    ROW_NUMBER() OVER(PARTITION BY ref.id_house, sim.id_house ORDER BY sim.iptu DESC) AS rn_iptu,
    ROW_NUMBER() OVER(PARTITION BY ref.id_house, sim.id_house ORDER BY sim.condo DESC) AS rn_condo
    FROM
      datalake_atlas_pricing_report.on_market_house_listings AS ref
    LEFT JOIN
      datalake_atlas_pricing_report.on_market_house_listings AS sim
        ON ref.house_type = sim.house_type
          AND sim.bedrooms BETWEEN ref.bedrooms - 1 AND ref.bedrooms + 1
          AND sim.total_area BETWEEN ref.total_area * 0.7 AND ref.total_area * 1.3
          AND ref.id_house <> sim.id_house
          AND ref.region_code = sim.region_code
          AND (sim.iptu IS NOT NULL OR sim.condo IS NOT NULL)
          AND sim.price BETWEEN ref.calculator_min_price AND ref.calculator_max_price
),
nearest_houses_condo AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY distance_km) AS similar_order
  FROM
    similar_houses
  WHERE
    distance_km <= 2
    AND rn_condo = 1
    AND similar_condo IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY distance_km) <= 30
),
nearest_houses_condo_fix AS (
  SELECT
    *
  FROM
    nearest_houses_condo
  QUALIFY
    MAX(similar_order) OVER(PARTITION BY id_house) >= 5
),
nearest_houses_iptu AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY distance_km) AS similar_order
  FROM
    similar_houses
  WHERE
    distance_km <= 2
    AND rn_iptu = 1
    AND similar_iptu IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY distance_km) <= 30
),
nearest_houses_iptu_fix AS (
  SELECT
    *
  FROM
    nearest_houses_iptu
  QUALIFY
    MAX(similar_order) OVER(PARTITION BY id_house) >= 5
),
all_similar_houses AS (
  SELECT
    id_house,
    similar_id_house,
    distance_km
  FROM
    nearest_houses_condo_fix
  UNION
  SELECT
    id_house,
    similar_id_house,
    distance_km
  FROM
    nearest_houses_iptu_fix
),
auxiliar_info AS (
  SELECT DISTINCT
    id_house,
    house_type,
    city,
    region_code,
    id_region,
    neighborhood
  FROM
    datalake_atlas_pricing_report.on_market_house_listings
)
SELECT
  result.id_house,
  result.similar_id_house,
  reference.id_region AS reference_id_region,
  similar.id_region AS similar_id_region,
  reference.region_code AS reference_region_code,
  similar.region_code AS similar_region_code,
  reference.house_type,
  reference.city,
  reference.neighborhood AS reference_neighborhood,
  similar.neighborhood AS similar_neighborhood,
  result.distance_km,
  result_condo.reference_condo,
  result_condo.similar_condo,
  result_iptu.reference_iptu,
  result_iptu.similar_iptu
FROM
  all_similar_houses AS result
INNER JOIN
  auxiliar_info AS reference
    ON reference.id_house = result.id_house
INNER JOIN
  auxiliar_info AS similar
    ON similar.id_house = result.similar_id_house
LEFT JOIN
  nearest_houses_condo_fix AS result_condo
    ON result_condo.id_house = result.id_house
      AND result_condo.similar_id_house = result.similar_id_house
LEFT JOIN
  nearest_houses_iptu_fix AS result_iptu
    ON result_iptu.id_house = result.id_house
      AND result_iptu.similar_id_house = result.similar_id_house
