WITH house AS (
  SELECT
    h.id,
    h.id_external,
    COUNT(*) OVER(PARTITION BY h.id_external) AS qt_house
  FROM
    datalake_ebdb_clean.house AS h
  WHERE
    h.id_external IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY h.id_external ORDER BY h.id DESC) = 1
),
bc_sale AS (
  SELECT
    bcd.id_lead,
    bcd.ts_created
  FROM
    datalake_brokers_supply_processor_clean.business_context_detail AS bcd
  WHERE
    bcd.business_context = 'SALE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bcd.id_lead ORDER BY bcd.ts_created DESC) = 1
),
bc_rent AS (
  SELECT
    bcd.id_lead,
    bcd.ts_created
  FROM
    datalake_brokers_supply_processor_clean.business_context_detail AS bcd
  WHERE
    bcd.business_context = 'RENT'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bcd.id_lead ORDER BY bcd.ts_created DESC) = 1
)
SELECT
  l.id AS id_lead_3p,
  l.id_by_real_estate,
  h.id AS id_house,
  l.uuid_lead,
  l.uuid_company,
  l.cnpj,
  l.lead_hash,
  -- location
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.address')), '') AS address,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.number')), '') AS number,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.floor')), '') AS floor,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.complement')), '') AS complement,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.neighborhood')), '') AS neighborhood,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.city')), '') AS city,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.stateAcronym')), '') AS state_acronym,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.country')), '') AS country,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.countryCode')), '') AS country_code,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.zipCode')), '') AS zip_code,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.lat')), '') AS DOUBLE) AS lat,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.lng')), '') AS DOUBLE) AS lng,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.regionId')), '') AS LONG) AS region_id,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.regionSlug')), '') AS region_slug,
  NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.referencePoint')), '') AS reference_point,
  -- pricing
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.pricing, '$.rent')), '') AS DOUBLE) AS rent,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.pricing, '$.salePrice')), '') AS DOUBLE) AS sale_price,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.pricing, '$.condoPrice')), '') AS DOUBLE) AS condo_price,
  -- blueprint
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.totalArea')), '') AS INT) AS total_area,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.bedrooms')), '') AS INT) AS bedrooms,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.suites')), '') AS INT) AS suites,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.bathrooms')), '') AS INT) AS bathrooms,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.garages')), '') AS INT) AS garages,
  NULLIF(TRIM(GET_JSON_OBJECT(l.blueprint, '$.houseType')), '') AS house_type,
  -- owner
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner, '$.email')), '') AS owner_email,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner, '$.name')), '') AS owner_name,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner, '$.phone')), '') AS owner_phone,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner, '$.personType')), '') AS owner_person_type,
  -- owner_agent
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.personUuid')), '') AS owner_agent_person_uuid,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.externalId')), '') AS owner_agent_external_id,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.name')), '') AS owner_agent_name,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.email')), '') AS owner_agent_email,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.phone')), '') AS owner_agent_phone,
  NULLIF(TRIM(GET_JSON_OBJECT(l.owner_agent, '$.relationship')), '') AS owner_agent_relationship,
  -- access
  NULLIF(TRIM(GET_JSON_OBJECT(l.access, '$.accessType')), '') AS access_type,
  NULLIF(TRIM(GET_JSON_OBJECT(l.access, '$.authorizationType')), '') AS authorization_type,
  NULLIF(TRIM(GET_JSON_OBJECT(l.access, '$.occupantType')), '') AS occupant_type,
  -- brokers
  NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.condominium')), '') AS condominium,
  NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.constructionYear')), '') AS construction_year,
  NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.block')), '') AS block,
  NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.tower')), '') AS tower,
  -- raw JSON columns
  l.details,
  l.photos,
  -- booleans
  l.is_sent_to_main,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.location, '$.outOfArea')), '') AS BOOLEAN) AS is_out_of_area,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.pricing, '$.iptuNotPaid')), '') AS BOOLEAN) AS is_iptu_not_paid,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.access, '$.hasRestriction')), '') AS BOOLEAN) AS has_restriction,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.balcony')), '') AS BOOLEAN) AS has_balcony,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.furnished')), '') AS BOOLEAN) AS is_furnished,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.habitat')), '') AS BOOLEAN) AS is_habitat,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.agencyKey')), '') AS BOOLEAN) AS has_agency_key,
  CAST(NULLIF(TRIM(GET_JSON_OBJECT(l.brokers, '$.concierge')), '') AS BOOLEAN) AS has_concierge,
  h.qt_house > 1 AS has_lead_house_conflicts,
  l.has_3p_access_control,
  l.ts_created AS ts_lead_created,
  l.ts_updated AS ts_lead_updated,
  FROM_UTC_TIMESTAMP(bs.ts_created, 'America/Sao_Paulo') AS ts_sale_business_context_created,
  FROM_UTC_TIMESTAMP(br.ts_created, 'America/Sao_Paulo') AS ts_rent_business_context_created,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(l.ts_updated) AS year,
  MONTH(l.ts_updated) AS month,
  DAY(l.ts_updated) AS day
FROM
  datalake_brokers_supply_processor_clean.lead_3p AS l
LEFT JOIN
  house AS h
    ON h.id_external = l.uuid_lead
LEFT JOIN
  bc_sale AS bs
    ON l.id = bs.id_lead
LEFT JOIN
  bc_rent AS br
    ON l.id = br.id_lead