WITH house_agregation_dates AS (
  SELECT
    id_house,
    FIRST(id_user) FILTER(WHERE cfl.business_context = 'SALE' AND id_user <> -1) AS id_ciq_user_sale,
    FIRST(id_partner) FILTER(WHERE cfl.business_context = 'SALE') AS id_partner_sale,
    FIRST(id_agent) FILTER(WHERE cfl.business_context = 'SALE') AS id_agent_sale,
    FIRST(uuid_person) FILTER(WHERE cfl.business_context = 'SALE') AS uuid_person_sale,
    FIRST(id_user) FILTER(WHERE cfl.business_context = 'RENT' AND id_user <> -1) AS id_ciq_user_rent,
    FIRST(id_partner) FILTER(WHERE cfl.business_context = 'RENT') AS id_partner_rent,
    FIRST(id_agent) FILTER(WHERE cfl.business_context = 'RENT') AS id_agent_rent,
    FIRST(uuid_person) FILTER(WHERE cfl.business_context = 'RENT') AS uuid_person_rent,
    FIRST(consultant_type) FILTER(WHERE cfl.business_context = 'SALE') AS consultant_type_sale,
    FIRST(consultant_type) FILTER(WHERE cfl.business_context = 'RENT') AS consultant_type_rent,
    COUNT(DISTINCT cfl.business_context) FILTER(WHERE cfl.has_first_listing IS TRUE) = 2 AS is_hybrid_house,
    MIN(cfl.ts_first_listing) FILTER(WHERE cfl.business_context = 'SALE') AS ts_first_listing_sale,
    MIN(cfl.ts_first_listing) FILTER(WHERE cfl.business_context = 'RENT') AS ts_first_listing_rent,
    MIN(cfl.ts_contract_signed) FILTER(WHERE cfl.business_context = 'SALE') AS ts_contract_signed_sale,
    MIN(cfl.ts_contract_signed) FILTER(WHERE cfl.business_context = 'RENT') AS ts_contract_signed_rent
  FROM
    datalake_listing_deduplication.first_listing AS cfl
  GROUP BY ALL
),
last_house_listing_status AS (
  SELECT
    id_house,
    status,
    business_context
  FROM
    datalake_listing_deduplication.first_listing AS cfl
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_house, business_context ORDER BY ts_updated DESC) = 1
),
house_listing_status_by_context AS (
  SELECT
    id_house,
    FIRST(status) FILTER(WHERE business_context = 'SALE') AS last_house_listing_status_sale,
    FIRST(status) FILTER(WHERE business_context = 'RENT') AS last_house_listing_status_rent
  FROM
    last_house_listing_status AS hls
  GROUP BY ALL
),
draft_contract AS (
  SELECT
    id_house,
    ts_contract_created
  FROM
    datalake_listing_contracts.listing_contracts
  WHERE
    contract_status = 'Minuta'
),
rent_ongoing_contract AS (
  SELECT
    c.id_house,
    c.is_ongoing_contract
  FROM
    datalake_ebdb_contract.contract AS c
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY c.id_house 
      ORDER BY c.ts_updated DESC
    ) = 1
),
indica_ai_listings AS (
  SELECT
    id_house,
    MIN(CASE WHEN id_referred_by > -1 AND application NOT IN ('consultantpwa', 'supplyprocessor') AND supply_source <> 'CIQ' THEN TRUE ELSE FALSE END) AS is_indica_ai,
    MIN(ts_event_original) AS first_event_date,
    MIN(business_context) AS business_context
  FROM
    datalake_supply_flows.supply_events_tracking
  WHERE 
    funnel_step = 'FIRST_LISTING'
  GROUP BY
    id_house
),
published_days AS (
  SELECT 
      id_house,
      SUM(CASE WHEN business_context = 'RENT' THEN DATEDIFF(
        LEAST(COALESCE(ts_state_ended, DATE(NOW())), ts_first_publication + INTERVAL 60 DAY), 
        GREATEST(ts_state_started, ts_first_publication)
      ) ELSE 0 END) AS total_days_published_within_60_days_rent,
      SUM(CASE WHEN business_context = 'SALE' THEN DATEDIFF(
        LEAST(COALESCE(ts_state_ended, DATE(NOW())), ts_first_publication + INTERVAL 60 DAY), 
        GREATEST(ts_state_started, ts_first_publication)
      ) ELSE 0 END) AS total_days_published_within_60_days_sale,
      MIN(ts_first_publication) FILTER(WHERE business_context = 'RENT') AS ts_first_publication_rent,
      ts_first_publication_rent + INTERVAL 60 DAY AS ts_60_days_after_first_publication_rent,
      MIN(ts_first_publication) FILTER(WHERE business_context = 'SALE') AS ts_first_publication_sale,
      ts_first_publication_sale + INTERVAL 60 DAY AS ts_60_days_after_first_publication_sale
  FROM 
    datalake_ebdb_listing.listing_business_context_status_history
  WHERE 
    status = 'PUBLISHED'
    AND ts_state_started < ts_first_publication + INTERVAL 60 DAY
  GROUP BY 1
),
accumulated_published_days AS (
  WITH accumulated_days AS (
    SELECT 
        bcsh.id_house,
        bcsh.business_context,
        CASE WHEN bcsh.business_context = 'RENT' THEN ad.date END AS dt_rent,
        CASE WHEN bcsh.business_context = 'SALE' THEN ad.date END AS dt_sale
    FROM 
      datalake_ebdb_listing.listing_business_context_status_history as bcsh 
    LEFT JOIN 
      datalake_quintoandar.aux_date as ad
        ON ad.date BETWEEN DATE(bcsh.ts_state_started) AND DATE(COALESCE(bcsh.ts_state_ended, NOW()))
    WHERE 
      bcsh.status = 'PUBLISHED'
      AND bcsh.ts_state_started < bcsh.ts_first_publication + INTERVAL 60 DAY
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY bcsh.id_house, bcsh.business_context ORDER BY ad.date) = 15
  )
  SELECT 
    id_house,
    MAX(dt_rent) AS dt_15_published_accumulated_days_rent,
    MAX(dt_sale) AS dt_15_published_accumulated_days_sale
  FROM 
    accumulated_days
  GROUP BY ALL
),
last_depub_dates AS (
  SELECT
    id_house,
    MAX(ts_state_started) AS ts_last_depub,
    MAX(ts_state_started) FILTER(WHERE business_context = 'SALE') AS ts_last_depub_sale,
    MAX(ts_state_started) FILTER(WHERE business_context = 'RENT') AS ts_last_depub_rent
  FROM
    datalake_ebdb_listing.listing_business_context_status_history
  WHERE
    status IN ('UNPUBLISHED', 'SUSPENDED', 'OPTED-OUT')
  GROUP BY ALL
)
SELECT
  h.id_house,
  h.id_ciq_user_sale AS id_user_listing_registrant_sale,
  h.uuid_person_sale,
  h.id_partner_sale,
  h.id_agent_sale,
  h.id_ciq_user_rent AS id_user_listing_registrant_rent,
  h.uuid_person_rent,
  h.id_partner_rent,
  h.id_agent_rent,
  ld.id_house AS id_house_duplicated,
  ld.id_user_listing_registrant_rent AS id_user_listing_registrant_rent_duplicated,
  ld.id_user_listing_registrant_sale AS id_user_listing_registrant_sale_duplicated,
  DATEDIFF(DATE(h.ts_contract_signed_rent), DATE(h.ts_first_listing_rent)) AS days_between_fl_to_cs,
  DATEDIFF(DATE(h.ts_contract_signed_sale), DATE(h.ts_first_listing_sale)) AS days_between_fl_to_ccv,
  ABS(DATEDIFF(h.ts_first_listing_rent, h.ts_first_listing_sale)) AS days_between_fl_hybrid,
  pd.total_days_published_within_60_days_rent,
  pd.total_days_published_within_60_days_sale,
  CASE
    WHEN h.is_hybrid_house THEN
      CASE
        WHEN h.ts_first_listing_sale > h.ts_first_listing_rent THEN 'RENT > SALE'
        WHEN h.ts_first_listing_sale < h.ts_first_listing_rent THEN 'SALE > RENT'
        ELSE 'CREATED AS A HYBRID' 
      END
    ELSE NULL
  END AS hybrid_creation_order,
  ld_source.supply_source AS supply_source,
  ld_source.supply_source_rent AS supply_source_rent,
  ld_source.supply_source_sale AS supply_source_sale,
  ld.supply_source AS supply_source_duplicated,
  ld.supply_source_rent AS supply_source_rent_duplicated,
  ld.supply_source_sale AS supply_source_sale_duplicated,
  h.consultant_type_rent,
  h.consultant_type_sale,
  hls.last_house_listing_status_rent,
  hls.last_house_listing_status_sale,
  CASE 
    WHEN h.ts_contract_signed_sale IS NOT NULL THEN 'SOLD'
    WHEN roc.is_ongoing_contract IS TRUE THEN 'RENTED'
    WHEN hls.last_house_listing_status_rent = 'PUBLISHED'
      OR hls.last_house_listing_status_sale =  'PUBLISHED'
      THEN 'PUBLISHED'
    WHEN COALESCE(hls.last_house_listing_status_rent, "N/D") IN ('UNPUBLISHED', 'OPTED_OUT', "N/D") 
      AND COALESCE(hls.last_house_listing_status_sale, "N/D") IN ('UNPUBLISHED', 'OPTED_OUT', "N/D")
      THEN 'UNPUBLISHED'
    WHEN COALESCE(hls.last_house_listing_status_rent, "N/D") IN ('UNPUBLISHED', 'OPTED_OUT', "N/D")
      AND hls.last_house_listing_status_sale IS NOT NULL 
      THEN hls.last_house_listing_status_sale
    WHEN COALESCE(hls.last_house_listing_status_sale, "N/D") IN ('UNPUBLISHED', 'OPTED_OUT', "N/D")
      AND hls.last_house_listing_status_rent IS NOT NULL 
      THEN hls.last_house_listing_status_rent
    ELSE COALESCE(hls.last_house_listing_status_rent, hls.last_house_listing_status_sale) 
  END AS house_listing_status,
  roc.is_ongoing_contract IS TRUE AS is_house_rented,
  h.ts_contract_signed_sale IS NOT NULL AS is_house_sold,
  h.is_hybrid_house,
  dc.id_house IS NOT NULL AND dc.ts_contract_created < (h.ts_first_listing_rent + INTERVAL 15 DAY) AS is_draft_contract,
  DATEDIFF(h.ts_contract_signed_rent, h.ts_first_listing_rent) <= 60 AS is_signed_cs_within_60_days,
  DATEDIFF(h.ts_contract_signed_sale, h.ts_first_listing_sale) <= 60 AS is_signed_ccv_within_60_days,
  ia.is_indica_ai,
  roc.is_ongoing_contract AS is_ongoing_rent_contract,
  apd.dt_15_published_accumulated_days_rent,
  apd.dt_15_published_accumulated_days_sale,
  dc.ts_contract_created AS ts_created_draft_contract_rent,
  h.ts_contract_signed_rent AS ts_first_contract_signed_rent,
  h.ts_contract_signed_sale AS ts_first_contract_signed_sale,
  LEAST(h.ts_first_listing_rent, h.ts_first_listing_sale) AS ts_first_listing,
  h.ts_first_listing_rent AS ts_initial_first_listing_rent,
  IF(
      h.is_hybrid_house IS TRUE AND hybrid_creation_order = 'RENT > SALE', 
      LEAST(h.ts_first_listing_rent, h.ts_first_listing_sale), 
      h.ts_first_listing_sale
  ) AS ts_initial_first_listing_sale,
  h.ts_first_listing_sale,
  h.ts_first_listing_rent,
  ldd.ts_last_depub AS ts_last_depublication,
  ldd.ts_last_depub_rent AS ts_last_depublication_rent,
  ldd.ts_last_depub_sale AS ts_last_depublication_sale,
  ldd_duplicated.ts_last_depub AS ts_last_depublication_duplicated,
  ldd_duplicated.ts_last_depub_rent AS ts_last_depublication_rent_duplicated,
  ldd_duplicated.ts_last_depub_sale AS ts_last_depublication_sale_duplicated
FROM
  house_agregation_dates AS h
LEFT JOIN
  indica_ai_listings AS ia
    ON h.id_house = ia.id_house
LEFT JOIN
  published_days AS pd
    ON h.id_house = pd.id_house
LEFT JOIN
  accumulated_published_days AS apd
    ON h.id_house = apd.id_house
LEFT JOIN
  draft_contract AS dc
    ON h.id_house = dc.id_house
LEFT JOIN
  house_listing_status_by_context AS hls
    ON h.id_house = hls.id_house
LEFT JOIN
  rent_ongoing_contract AS roc
    ON roc.id_house = h.id_house
LEFT JOIN
  last_depub_dates AS ldd
    ON h.id_house = ldd.id_house
LEFT JOIN
  datalake_listing_deduplication.listing_deduplication AS ld_source
    ON h.id_house = ld_source.id_house
LEFT JOIN
  datalake_listing_deduplication.listing_deduplication AS ld
    ON h.id_house = ld.id_house_duplicated
    AND ld.is_duplicated
LEFT JOIN
  last_depub_dates AS ldd_duplicated
    ON ld.id_house = ldd_duplicated.id_house