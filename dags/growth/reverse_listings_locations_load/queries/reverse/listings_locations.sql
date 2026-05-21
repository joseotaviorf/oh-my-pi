WITH region_settings AS (
  SELECT
    region_config.id_region,
    region_config.featured_rank,
    COLLECT_SET(region_parameters.business_context) AS ebdb_enabled_business_contexts,
    STRUCT(
      STRUCT(
        MAX(
          CASE
            WHEN region_parameters.business_context = 'RENT'
              THEN region_parameters.min_price
            ELSE 0
          END
        ) AS min,
        MAX(
          CASE
            WHEN region_parameters.business_context = 'RENT'
              THEN region_parameters.max_price
            ELSE 0
          END
        ) AS max
      ) AS rent,
      STRUCT(
        MAX(
          CASE
            WHEN region_parameters.business_context = 'SALE'
              THEN region_parameters.min_price
            ELSE 0
          END
        ) AS min,
        MAX(
          CASE
            WHEN region_parameters.business_context = 'SALE'
              THEN region_parameters.max_price
            ELSE 0
          END
        ) AS max
      ) AS sale
    ) AS prices
  FROM
    datalake_ebdb_clean.region_config AS region_config
  LEFT JOIN
    datalake_ebdb_clean.region_parameters AS region_parameters
      ON region_config.id = region_parameters.id_region_config
  WHERE
    region_parameters.is_search_enabled = TRUE
  GROUP BY
    region_config.id_region,
    region_config.featured_rank
),
deduplicated_cities AS (
  SELECT
    short_region_name,
    LOWER(name) AS city_name_lower,
    MIN(id) AS city_id
  FROM
    dw_public.dim_region
  WHERE
    level = 'Cidade'
  GROUP BY
    short_region_name,
    LOWER(name)
),
deduplicated_neighborhoods AS (
  SELECT
    parent_city.id AS city_id,
    LOWER(neighborhood.name) AS neighborhood_name_lower,
    MIN(neighborhood.id) AS neighborhood_id
  FROM
    dw_public.dim_region AS neighborhood
  INNER JOIN
    dw_public.dim_region AS parent_city
      ON neighborhood.city_id = parent_city.id
      AND parent_city.level = 'Cidade'
  WHERE
    neighborhood.level = 'SubRegiao'
  GROUP BY
    parent_city.id,
    LOWER(neighborhood.name)
),
normalized_addresses AS (
  SELECT
    compounds.address.state_code,
    compounds.address.city AS original_city,
    compounds.address.neighborhood AS original_neighborhood,
    compounds.address.street AS original_street,
    TRANSLATE(
      LOWER(compounds.address.city),
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    ) AS normalized_city,
    TRANSLATE(
      LOWER(compounds.address.neighborhood),
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    ) AS normalized_neighborhood,
    TRANSLATE(
      LOWER(compounds.address.street),
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    ) AS normalized_street
  FROM
    vespucio_prod_delta.house_compounds AS compounds
  WHERE
    compounds.address.country_code = 'BR'
    AND compounds.address.city IS NOT NULL
    AND TRIM(compounds.address.city) != ''
    AND compounds.address.neighborhood IS NOT NULL
    AND TRIM(compounds.address.neighborhood) != ''
    AND compounds.address.street IS NOT NULL
    AND TRIM(compounds.address.street) != ''
),
city_mode AS (
  SELECT
    state_code,
    normalized_city,
    original_city AS mode_city
  FROM (
    SELECT
      state_code,
      normalized_city,
      original_city,
      ROW_NUMBER() OVER (
        PARTITION BY state_code, normalized_city
        ORDER BY COUNT(*) DESC, original_city
      ) AS rn
    FROM
      normalized_addresses
    GROUP BY
      state_code,
      normalized_city,
      original_city
  ) AS ranked
  WHERE
    rn = 1
),
neighborhood_mode AS (
  SELECT
    state_code,
    normalized_city,
    normalized_neighborhood,
    original_neighborhood AS mode_neighborhood
  FROM (
    SELECT
      state_code,
      normalized_city,
      normalized_neighborhood,
      original_neighborhood,
      ROW_NUMBER() OVER (
        PARTITION BY state_code, normalized_city, normalized_neighborhood
        ORDER BY COUNT(*) DESC, original_neighborhood
      ) AS rn
    FROM
      normalized_addresses
    GROUP BY
      state_code,
      normalized_city,
      normalized_neighborhood,
      original_neighborhood
  ) AS ranked
  WHERE
    rn = 1
),
street_mode AS (
  SELECT
    state_code,
    normalized_city,
    normalized_neighborhood,
    normalized_street,
    original_street AS mode_street
  FROM (
    SELECT
      state_code,
      normalized_city,
      normalized_neighborhood,
      normalized_street,
      original_street,
      ROW_NUMBER() OVER (
        PARTITION BY state_code, normalized_city, normalized_neighborhood, normalized_street
        ORDER BY COUNT(*) DESC, original_street
      ) AS rn
    FROM
      normalized_addresses
    GROUP BY
      state_code,
      normalized_city,
      normalized_neighborhood,
      normalized_street,
      original_street
  ) AS ranked
  WHERE
    rn = 1
),
base_listings AS (
  SELECT
    listings.dejavuid,
    dn.neighborhood_id,
    dc.city_id,
    sm.mode_street AS street,
    nm.mode_neighborhood AS neighborhood,
    cm.mode_city AS city,
    compounds.address.state_code,
    state_dim.name AS state,
    compounds.address.country_code,
    country_dim.name AS country,
    compounds.lat,
    compounds.lng,
    region_settings.ebdb_enabled_business_contexts,
    region_settings.featured_rank,
    region_settings.prices,
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
    datalake_ebdb_clean.country AS country_dim
      ON country_dim.id = state_dim.id_country
  LEFT JOIN
    deduplicated_cities AS dc
      ON dc.city_name_lower = LOWER(compounds.address.city)
      AND dc.short_region_name = state_dim.abbreviation
  LEFT JOIN
    deduplicated_neighborhoods AS dn
      ON dn.neighborhood_name_lower = LOWER(compounds.address.neighborhood)
      AND dn.city_id = dc.city_id
  LEFT JOIN
    region_settings
      ON region_settings.id_region = dc.city_id
  LEFT JOIN
    city_mode AS cm
      ON cm.state_code = compounds.address.state_code
      AND cm.normalized_city = TRANSLATE(
        LOWER(compounds.address.city),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
  LEFT JOIN
    neighborhood_mode AS nm
      ON nm.state_code = compounds.address.state_code
      AND nm.normalized_city = TRANSLATE(
        LOWER(compounds.address.city),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
      AND nm.normalized_neighborhood = TRANSLATE(
        LOWER(compounds.address.neighborhood),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
  LEFT JOIN
    street_mode AS sm
      ON sm.state_code = compounds.address.state_code
      AND sm.normalized_city = TRANSLATE(
        LOWER(compounds.address.city),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
      AND sm.normalized_neighborhood = TRANSLATE(
        LOWER(compounds.address.neighborhood),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
      AND sm.normalized_street = TRANSLATE(
        LOWER(compounds.address.street),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      )
  WHERE
    listings.source_name IN ('ebdb_houses', 'navent_houses')
    AND compounds.address.country_code = 'BR'
    AND listings.status = 'PUBLISHED'
    AND listings.business_context IN ('RENT', 'SALE')
    AND compounds.address.city IS NOT NULL
    AND TRIM(compounds.address.city) != ''
    AND compounds.address.neighborhood IS NOT NULL
    AND TRIM(compounds.address.neighborhood) != ''
    AND compounds.address.street IS NOT NULL
    AND TRIM(compounds.address.street) != ''
  GROUP BY
    listings.dejavuid,
    dn.neighborhood_id,
    dc.city_id,
    sm.mode_street,
    nm.mode_neighborhood,
    cm.mode_city,
    compounds.address.state_code,
    state_dim.name,
    compounds.address.country_code,
    country_dim.name,
    compounds.lat,
    compounds.lng,
    region_settings.ebdb_enabled_business_contexts,
    region_settings.featured_rank,
    region_settings.prices
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
  ), x -> x IS NOT NULL) AS business_contexts,
  ebdb_enabled_business_contexts,
  featured_rank,
  prices
FROM
  base_listings
GROUP BY GROUPING SETS (
  (neighborhood_id, city_id, street, neighborhood, city, state_code, state, country_code, country),
  (neighborhood_id, city_id, neighborhood, city, state_code, state, country_code, country),
  (city_id, city, state_code, state, country_code, country, ebdb_enabled_business_contexts, featured_rank, prices)
)
