WITH on_market_listings AS (
  SELECT
    id_house,
    id_region,
    region_code,
    city,
    neighborhood,
    business_context,
    house_status,
    house_type,
    rent_total_value,
    price,
    sale_price_m2,
    calculator_min_price,
    calculator_max_price,
    days_in_the_market,
    lat,
    lng,
    total_area,
    bedrooms
  FROM
    datalake_atlas_pricing_report.on_market_house_listings
),
negotiation_listings_ranked AS (
  SELECT
    id_house,
    id_region,
    region_code,
    city,
    neighborhood,
    business_context,
    house_status,
    house_type,
    rent_total_value,
    price,
    sale_price_m2,
    NULL AS calculator_min_price,
    NULL AS calculator_max_price,
    days_in_the_market,
    lat,
    lng,
    total_area,
    bedrooms,
    ts_status_started,
    ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started DESC) AS rn
  FROM
    datalake_atlas_pricing_report.status_history_house_negotiation
  WHERE
    (business_context = 'RENT' AND days_in_the_market <= 365)
    OR
    (business_context = 'SALE' AND days_in_the_market <= 730)
),
all_listings AS (
  SELECT
    id_house,
    id_region,
    region_code,
    city,
    neighborhood,
    business_context,
    house_status,
    house_type,
    rent_total_value,
    price,
    sale_price_m2,
    calculator_min_price,
    calculator_max_price,
    days_in_the_market,
    lat,
    lng,
    total_area,
    bedrooms
  FROM
    on_market_listings
  UNION ALL
  SELECT
    id_house,
    id_region,
    region_code,
    city,
    neighborhood,
    business_context,
    house_status,
    house_type,
    rent_total_value,
    price,
    sale_price_m2,
    calculator_min_price,
    calculator_max_price,
    days_in_the_market,
    lat,
    lng,
    total_area,
    bedrooms
  FROM
    negotiation_listings_ranked
  WHERE
    rn = 1
),
neighborhood_similar_houses AS (
  SELECT
    ref.id_house,
    sim.id_house AS similar_id_house,
    ref.business_context,
    sim.house_status,
    ref.rent_total_value AS reference_rent_total_value,
    sim.rent_total_value AS similar_rent_total_value,
    ref.price AS reference_price,
    sim.price AS similar_price,
    ref.sale_price_m2 AS reference_sale_price_m2,
    sim.sale_price_m2 AS similar_sale_price_m2,
    ref.days_in_the_market AS reference_days_in_the_market,
    sim.days_in_the_market AS similar_days_in_the_market,
    6371 * 2 * ASIN(
                SQRT(
                  POWER(SIN(RADIANS(sim.lat - ref.lat)/2),2) +
                  COS(RADIANS(ref.lat)) * COS(RADIANS(sim.lat)) *
                  POWER(SIN(RADIANS(sim.lng - ref.lng) / 2), 2)
                )
    ) AS distance_km
  FROM
    datalake_atlas_pricing_report.on_market_house_listings AS ref
  LEFT JOIN
    all_listings AS sim
      ON ref.business_context = sim.business_context
        AND ref.house_type = sim.house_type
        AND sim.bedrooms BETWEEN ref.bedrooms - 1 AND ref.bedrooms + 1
        AND sim.total_area BETWEEN ref.total_area * 0.7 AND ref.total_area * 1.3
        AND ref.id_house <> sim.id_house
        AND ref.id_region = sim.id_region
        AND sim.price BETWEEN ref.calculator_min_price AND ref.calculator_max_price
),
nearest_houses_ranked AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km,
    ROW_NUMBER() OVER(PARTITION BY id_house, business_context, house_status ORDER BY distance_km) AS similar_order
  FROM
    neighborhood_similar_houses
  WHERE
    distance_km <= 2
),
nearest_houses AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km
  FROM
    nearest_houses_ranked
  WHERE
    similar_order <= 30
),
similar_houses_recovery AS (
  SELECT
    id_house,
    business_context,
    house_status,
    COUNT(similar_id_house) AS total_similar_houses
  FROM
    nearest_houses
  GROUP BY
    id_house,
    business_context,
    house_status
  HAVING
    COUNT(similar_id_house) < 5
),
region_similar_houses AS (
  SELECT
    ref.id_house,
    sim.id_house AS similar_id_house,
    ref.business_context,
    sim.house_status,
    ref.rent_total_value AS reference_rent_total_value,
    sim.rent_total_value AS similar_rent_total_value,
    ref.price AS reference_price,
    sim.price AS similar_price,
    ref.sale_price_m2 AS reference_sale_price_m2,
    sim.sale_price_m2 AS similar_sale_price_m2,
    ref.days_in_the_market AS reference_days_in_the_market,
    sim.days_in_the_market AS similar_days_in_the_market,
    6371 * 2 * ASIN(
                SQRT(
                  POWER(SIN(RADIANS(sim.lat - ref.lat)/2),2) +
                  COS(RADIANS(ref.lat)) * COS(RADIANS(sim.lat)) *
                  POWER(SIN(RADIANS(sim.lng - ref.lng) / 2), 2)
                )
    ) AS distance_km
  FROM
    similar_houses_recovery AS rec
  INNER JOIN
    datalake_atlas_pricing_report.on_market_house_listings AS ref
      ON rec.id_house = ref.id_house
        AND rec.business_context = ref.business_context
  LEFT JOIN
    all_listings AS sim
      ON ref.business_context = sim.business_context
        AND ref.house_type = sim.house_type
        AND rec.house_status = sim.house_status
        AND sim.bedrooms BETWEEN ref.bedrooms - 1 AND ref.bedrooms + 1
        AND sim.total_area BETWEEN ref.total_area * 0.7 AND ref.total_area * 1.3
        AND ref.id_house <> sim.id_house
        AND ref.region_code = sim.region_code
        AND sim.price BETWEEN ref.calculator_min_price AND ref.calculator_max_price
),
nearest_recovered_houses_ranked AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km,
    ROW_NUMBER() OVER(PARTITION BY id_house, business_context, house_status ORDER BY distance_km) AS similar_order
  FROM
    region_similar_houses
  WHERE
    distance_km <= 2
),
nearest_recovered_houses AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km,
    similar_order
  FROM
    nearest_recovered_houses_ranked
  WHERE
    similar_order <= 30
),
nearest_recovered_houses_with_max AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km,
    similar_order,
    MAX(similar_order) OVER(PARTITION BY id_house, business_context, house_status) AS max_similar_order
  FROM
    nearest_recovered_houses
),
nearest_recovered_houses_fix AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km
  FROM
    nearest_recovered_houses_with_max
  WHERE
    max_similar_order >= 5
),
nearest_houses_with_count AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km,
    COUNT(similar_id_house) OVER(PARTITION BY id_house, business_context, house_status) AS similar_count
  FROM
    nearest_houses
),
all_similar_houses AS (
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km
  FROM
    nearest_houses_with_count
  WHERE
    similar_count >= 5
  UNION ALL
  SELECT
    id_house,
    similar_id_house,
    business_context,
    house_status,
    reference_rent_total_value,
    similar_rent_total_value,
    reference_price,
    similar_price,
    reference_sale_price_m2,
    similar_sale_price_m2,
    reference_days_in_the_market,
    similar_days_in_the_market,
    distance_km
  FROM
    nearest_recovered_houses_fix
)
SELECT
  result.id_house,
  result.similar_id_house,
  reference.id_region AS reference_id_region,
  similar.id_region AS similar_id_region,
  reference.region_code AS reference_region_code,
  similar.region_code AS similar_region_code,
  result.business_context,
  reference.house_type,
  reference.city,
  reference.neighborhood AS reference_neighborhood,
  similar.neighborhood AS similar_neighborhood,
  reference.house_status AS reference_house_status,
  result.house_status AS similar_house_status,
  result.distance_km,
  result.reference_rent_total_value,
  result.similar_rent_total_value,
  result.reference_price,
  result.similar_price,
  result.reference_sale_price_m2,
  result.similar_sale_price_m2,
  result.reference_days_in_the_market,
  result.similar_days_in_the_market
FROM
  all_similar_houses AS result
INNER JOIN
  datalake_atlas_pricing_report.on_market_house_listings AS reference
    ON reference.id_house = result.id_house
      AND reference.business_context = result.business_context
INNER JOIN
  all_listings AS similar
    ON similar.id_house = result.similar_id_house
      AND similar.business_context = result.business_context
      AND similar.house_status = result.house_status
