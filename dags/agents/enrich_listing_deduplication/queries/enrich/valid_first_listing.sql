WITH house_agregation_dates AS (
  SELECT
    id_house,
    FIRST(id_user) FILTER(WHERE cfl.business_context = 'SALE') AS id_ciq_user_sale,
    FIRST(id_partner) FILTER(WHERE cfl.business_context = 'SALE') AS id_partner_sale,
    FIRST(uuid_person) FILTER(WHERE cfl.business_context = 'SALE') AS id_ciq_uuid_person_sale,
    FIRST(id_user) FILTER(WHERE cfl.business_context = 'RENT') AS id_ciq_user_rent,
    FIRST(id_partner) FILTER(WHERE cfl.business_context = 'RENT') AS id_partner_rent,
    FIRST(uuid_person) FILTER(WHERE cfl.business_context = 'RENT') AS id_ciq_uuid_person_rent,
    COUNT(DISTINCT cfl.business_context) FILTER(WHERE cfl.has_first_listing IS TRUE) = 2 AS is_hybrid_house,
    MIN(cfl.ts_first_listing) FILTER(WHERE cfl.business_context = 'SALE') AS ts_first_listing_sale,
    MIN(cfl.ts_first_listing) FILTER(WHERE cfl.business_context = 'RENT') AS ts_first_listing_rent,
    MIN(cfl.ts_contract_signed) FILTER(WHERE cfl.business_context = 'SALE') AS ts_contract_signed_sale,
    MIN(cfl.ts_contract_signed) FILTER(WHERE cfl.business_context = 'RENT') AS ts_contract_signed_rent
  FROM
    datalake_listing_deduplication.ciq_first_listing AS cfl
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
  h.id_ciq_uuid_person_sale AS id_uuid_person_sale,
  h.id_partner_sale,
  h.id_ciq_user_rent AS id_user_listing_registrant_rent,
  h.id_ciq_uuid_person_rent AS id_uuid_person_rent,
  h.id_partner_rent,
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
  ld.supply_source_rent AS supply_source_rent_duplicated,
  ld.supply_source_sale AS supply_source_sale_duplicated,
  h.is_hybrid_house,
  dc.id_house IS NOT NULL AND dc.ts_contract_created < (h.ts_first_listing_rent + INTERVAL 15 DAY) AS is_draft_contract,
  DATEDIFF(h.ts_contract_signed_rent, h.ts_first_listing_rent) <= 60 AS is_signed_cs_within_60_days,
  DATEDIFF(h.ts_contract_signed_sale, h.ts_first_listing_sale) <= 60 AS is_signed_ccv_within_60_days,
  ia.is_indica_ai,
  ld.ts_contract_signed_sale IS NOT NULL AS is_sold_duplicated,
  ld.ts_contract_signed_rent IS NOT NULL AS is_rented_duplicated,
  apd.dt_15_published_accumulated_days_rent,
  apd.dt_15_published_accumulated_days_sale,
  dc.ts_contract_created AS ts_created_draft_contract_rent,
  h.ts_contract_signed_rent AS ts_first_contract_signed_rent,
  h.ts_contract_signed_sale AS ts_first_contract_signed_sale,
  h.ts_first_listing_rent AS ts_initial_first_listing_rent,
  CASE 
    WHEN h.ts_first_listing_sale > h.ts_first_listing_rent THEN h.ts_first_listing_rent 
    WHEN h.ts_first_listing_sale < h.ts_first_listing_rent THEN h.ts_first_listing_sale 
    ELSE h.ts_first_listing_rent
  END AS ts_initial_first_listing_sale,
  h.ts_first_listing_sale,
  h.ts_first_listing_rent,
  ldd.ts_last_depub_rent AS ts_last_depublication_rent_duplicated,
  ldd.ts_last_depub_sale AS ts_last_depublication_sale_duplicated
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
  datalake_listing_deduplication.listing_deduplication AS ld
    ON h.id_house = ld.id_house_duplicated
    AND ld.is_duplicated
LEFT JOIN
  last_depub_dates AS ldd
    ON ld.id_house_duplicated = ldd.id_house