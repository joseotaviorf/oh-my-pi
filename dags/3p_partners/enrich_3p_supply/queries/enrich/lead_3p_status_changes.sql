WITH source_joined AS (
  SELECT
    bcd.id_lead AS id_lead_3p,
    bcd.business_context,
    bcda.status,
    bcda.status_reason,
    ri.ts_created AS ts_revision,
    bcd.has_3p_access_control,
    bcd.ts_created
  FROM
    datalake_brokers_supply_processor_clean.business_context_detail_aud AS bcda
  INNER JOIN
    datalake_brokers_supply_processor_clean.business_context_detail AS bcd
      ON bcda.id = bcd.id
  INNER JOIN
    datalake_brokers_supply_processor_clean.rev_info AS ri
      ON bcda.rev = ri.rev
),
status_timeline AS (
  SELECT
    sj.id_lead_3p,
    CASE
      WHEN CAST(NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.duplicateId'), '') AS INT) != 0
        AND GET_JSON_OBJECT(sj.status_reason, '$.duplicateHouse') != 'false'
      THEN CAST(GET_JSON_OBJECT(sj.status_reason, '$.duplicateId') AS INT)
    END AS id_duplicated_house,
    sj.business_context,
    sj.status,
    MAP_KEYS(MAP_FILTER(FROM_JSON(sj.status_reason, 'MAP<STRING, STRING>'), (k, v) -> v = 'true')) AS status_reason,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.listOfNotEligibleReasonsMessages'), ''), 'ARRAY<STRING>') AS not_eligible_pendings,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.listOfPendingReasonsMessages'), ''), 'ARRAY<STRING>') AS eligible_pendings,
    ROW_NUMBER() OVER (PARTITION BY sj.id_lead_3p, sj.business_context ORDER BY sj.ts_revision ASC) AS version,
    SIZE(
      FROM_JSON(
        NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.listOfNotEligibleReasonsMessages'), ''),
        'ARRAY<STRING>'
      )
    ) > 0 AS is_not_eligible_pending,
    SIZE(
      FROM_JSON(
        NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.listOfPendingReasonsMessages'), ''),
        'ARRAY<STRING>'
      )
    ) > 0 AS is_eligible_pending,
    sj.has_3p_access_control,
    sj.ts_revision AS ts_start,
    LEAD(sj.ts_revision) OVER (PARTITION BY sj.id_lead_3p, sj.business_context ORDER BY sj.ts_revision ASC) AS ts_end,
    sj.ts_created
  FROM
    source_joined AS sj
)
SELECT
  st.id_lead_3p,
  st.id_duplicated_house,
  st.business_context,
  st.status,
  st.status_reason,
  st.not_eligible_pendings,
  st.eligible_pendings,
  CASE
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('duplicateHouse', 'hybridLead', 'duplicateLead'),
        st.status_reason)) >= 1
    THEN 'DUPLICATED'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('invalidCompany', 'notAcceptedAuthorizationType', 'outsidePolygon', 'primaryHouse', 'notAcceptedHouseType', 'otherThirdPartner', 'ownerBlocked', 'outOfPriceRange'),
        st.status_reason)) >= 1
    THEN 'NO_OPERATIONAL_INTEREST'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('photoUrlRequiresHttps', 'photoAnalysisFlowFailure', 'unableToAccessExternalUrl', 'lessThanFourPhotos', 'poorImageQuality', 'photosInformationMissing'),
        st.status_reason)) >= 1
    THEN 'PHOTOS'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('invalidPhoneType', 'noOwnerPhone', 'noOwnerName', 'ownerInformationMissing', 'noSufficientOwnerData'),
        st.status_reason)) >= 1
    THEN 'OWNER_INFO'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('incompleteLocation', 'numberOfSuitesGreaterThanBedroomsOrBathrooms', 'outHouseMinSize', 'numberOfRoomsNotValid', 'wrongIptuValue', 'oldUpdated', 'locationInformationMissing'),
        st.status_reason)) >= 1
    THEN 'LISTING_INFO'
    WHEN SIZE(st.status_reason) > 0 THEN 'OTHER'
    ELSE 'N/A'
  END AS reason_macro,
  st.version,
  st.is_not_eligible_pending,
  st.is_eligible_pending,
  CASE
    WHEN NOT st.is_not_eligible_pending
      AND st.is_eligible_pending
      AND st.status = 'NOT_CONVERTED'
    THEN TRUE
    ELSE FALSE
  END AS is_opportunity,
  (st.version = 1 AND st.business_context = 'SALE') AS is_first_sale_status,
  (st.version = 1 AND st.business_context = 'RENT') AS is_first_rent_status,
  st.ts_end IS NULL AS is_current,
  st.has_3p_access_control,
  st.ts_start,
  st.ts_end,
  MIN(CASE WHEN st.status IN ('REGISTERED', 'UNPUBLISHED') THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_first_registered_from_bsp_to_main,
  MIN(CASE WHEN st.status = 'UNPUBLISHED' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_unpublished_in_bsp,
  MIN(CASE WHEN st.status = 'DISCARDED' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_discarded_in_bsp,
  MIN(CASE WHEN st.status = 'NOT_CONVERTED' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_first_not_converted_in_bsp,
  MAX(CASE WHEN st.status = 'NOT_CONVERTED' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_last_not_converted_in_bsp,
  MIN(CASE WHEN st.status = 'PROCESSING' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_first_processing_photos_in_bsp,
  MAX(CASE WHEN st.status = 'PROCESSING' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_last_processing_photos_in_bsp,
  MIN(CASE WHEN st.status = 'SUSPENDED' THEN st.ts_start END)
      OVER (PARTITION BY st.id_lead_3p, st.business_context ORDER BY st.ts_start) AS ts_suspended_in_bsp,
  CURRENT_TIMESTAMP() AS ts_load,
  FROM_UTC_TIMESTAMP(st.ts_created, 'America/Sao_Paulo') AS ts_business_context_created,
  YEAR(st.ts_start) AS year,
  MONTH(st.ts_start) AS month,
  DAY(st.ts_start) AS day
FROM
  status_timeline AS st
