WITH reason_categories AS (
  SELECT
    COLLECT_LIST(CASE WHEN reason_type = 'ENRICHMENT_REASON' THEN reason_name END) AS enrichment_reasons,
    COLLECT_LIST(CASE WHEN reason_type = 'INELIGIBLE_REASON' THEN reason_name END) AS ineligible_reasons,
    COLLECT_LIST(CASE WHEN reason_type = 'DISCARD_REASON' THEN reason_name END) AS discard_reasons
  FROM
    datalake_gsheets_clean.supply_processor_status_reasons
),
owner_changes AS (
  SELECT
    id,
    owner,
    ts_updated
  FROM
    datalake_brokers_supply_processor_clean.lead_3p_aud
  WHERE
    rev_type = 0
    OR mod_owner
),
source_with_owner AS (
  SELECT
    bcda.rev,
    bcd.id_lead AS id_lead_3p,
    bcd.business_context,
    bcda.status,
    bcda.status_reason,
    ri.ts_created AS ts_revision,
    bcd.has_3p_access_control,
    bcd.ts_created,
    la.owner,
    ROW_NUMBER() OVER (
      PARTITION BY bcda.id, bcda.rev
      ORDER BY la.ts_updated DESC
    ) AS rn_owner
  FROM
    datalake_brokers_supply_processor_clean.business_context_detail_aud AS bcda
  INNER JOIN
    datalake_brokers_supply_processor_clean.business_context_detail AS bcd
      ON bcda.id = bcd.id
  INNER JOIN
    datalake_brokers_supply_processor_clean.rev_info AS ri
      ON bcda.rev = ri.rev
  LEFT JOIN
    owner_changes AS la
      ON la.id = bcd.id_lead
      AND la.ts_updated <= bcda.ts_updated
),
source_joined AS (
  SELECT
    rev,
    id_lead_3p,
    business_context,
    status,
    status_reason,
    ts_revision,
    has_3p_access_control,
    ts_created,
    GET_JSON_OBJECT(owner, '$.phone') IS NOT NULL AS has_owner_info
  FROM
    source_with_owner
  WHERE
    rn_owner = 1
),
status_timeline AS (
  SELECT
    sj.rev,
    CASE
      WHEN sj.business_context = 'SALE' THEN sj.id_lead_3p * 10
      WHEN sj.business_context = 'RENT' THEN sj.id_lead_3p * 10 + 1
    END AS sk_lead_3p_flow,
    sj.id_lead_3p,
    CASE
      WHEN CAST(NULLIF(GET_JSON_OBJECT(sj.status_reason, '$.duplicateId'), '') AS INT) != 0
        AND GET_JSON_OBJECT(sj.status_reason, '$.duplicateHouse') != 'false'
      THEN CAST(GET_JSON_OBJECT(sj.status_reason, '$.duplicateId') AS INT)
    END AS sk_house_duplicated,
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
    sj.has_owner_info,
    sj.has_3p_access_control,
    sj.ts_revision AS ts_start,
    LEAD(sj.ts_revision) OVER (PARTITION BY sj.id_lead_3p, sj.business_context ORDER BY sj.ts_revision ASC) AS ts_end,
    sj.ts_created
  FROM
    source_joined AS sj
),
status_with_flags AS (
  SELECT
    st.rev,
    st.sk_lead_3p_flow,
    st.id_lead_3p,
    st.sk_house_duplicated,
    st.business_context,
    st.status,
    st.status_reason,
    st.not_eligible_pendings,
    st.eligible_pendings,
    st.version,
    st.is_not_eligible_pending,
    st.is_eligible_pending,
    st.has_owner_info,
    st.has_3p_access_control,
    st.ts_start,
    st.ts_end,
    st.ts_created,
    COALESCE(ARRAYS_OVERLAP(st.status_reason, rc.enrichment_reasons), FALSE) AS is_waiting_for_enrichment,
    COALESCE(ARRAYS_OVERLAP(st.status_reason, rc.ineligible_reasons), FALSE) AS is_ineligible,
    COALESCE(ARRAYS_OVERLAP(st.status_reason, rc.discard_reasons), FALSE) AS is_discarded
  FROM
    status_timeline AS st
  CROSS JOIN
    reason_categories AS rc
)
SELECT
  swf.rev AS id_status_changes,
  swf.sk_lead_3p_flow,
  swf.id_lead_3p,
  swf.sk_house_duplicated,
  swf.business_context,
  swf.status,
  swf.status_reason,
  swf.not_eligible_pendings,
  swf.eligible_pendings,
  CASE
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('duplicateHouse', 'hybridLead', 'duplicateLead'),
        swf.status_reason)) >= 1
    THEN 'DUPLICATED'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('invalidCompany', 'notAcceptedAuthorizationType', 'outsidePolygon', 'primaryHouse', 'notAcceptedHouseType', 'otherThirdPartner', 'ownerBlocked', 'outOfPriceRange'),
        swf.status_reason)) >= 1
    THEN 'NO_OPERATIONAL_INTEREST'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('photoUrlRequiresHttps', 'photoAnalysisFlowFailure', 'unableToAccessExternalUrl', 'lessThanFourPhotos', 'poorImageQuality', 'photosInformationMissing','imageAnalysisRejected'),
        swf.status_reason)) >= 1
    THEN 'PHOTOS'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY('invalidPhoneType', 'noOwnerPhone', 'noOwnerName', 'ownerInformationMissing', 'noSufficientOwnerData'),
        swf.status_reason)) >= 1
    THEN 'OWNER_INFO'
    WHEN CARDINALITY(ARRAY_INTERSECT(
      ARRAY(
        'incompleteLocation',
        'numberOfSuitesGreaterThanBedroomsOrBathrooms',
        'outHouseMinSize',
        'numberOfRoomsNotValid',
        'wrongIptuValue',
        'oldUpdated',
        'locationInformationMissing',
        'unparseableAddressComplement',
        'addressComplementStructMismatch',
        'incompleteLocationStreet',
        'incompleteLocationNumber',
        'incompleteLocationComplement',
        'incompleteLocationZipcode'
      ),
        swf.status_reason)) >= 1
    THEN 'LISTING_INFO'
    WHEN SIZE(swf.status_reason) > 0 THEN 'OTHER'
    ELSE 'N/A'
  END AS reason_macro,
  swf.version,
  swf.is_not_eligible_pending,
  swf.is_eligible_pending,
  swf.is_waiting_for_enrichment,
  swf.is_ineligible,
  swf.is_discarded,
  swf.has_owner_info,
  CASE
    WHEN NOT swf.is_not_eligible_pending
      AND swf.is_eligible_pending
      AND swf.status = 'NOT_CONVERTED'
    THEN TRUE
    ELSE FALSE
  END AS is_opportunity,
  (swf.version = 1 AND swf.business_context = 'SALE') AS is_first_sale_status,
  (swf.version = 1 AND swf.business_context = 'RENT') AS is_first_rent_status,
  swf.ts_end IS NULL AS is_current,
  swf.has_3p_access_control,
  swf.ts_start,
  swf.ts_end,
  MIN(CASE WHEN swf.status IN ('REGISTERED', 'UNPUBLISHED') THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_first_registered_from_bsp_to_main,
  MIN(CASE WHEN swf.status = 'UNPUBLISHED' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_unpublished_in_bsp,
  MIN(CASE WHEN swf.status = 'DISCARDED' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_discarded_in_bsp,
  MIN(CASE WHEN swf.status = 'NOT_CONVERTED' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_first_not_converted_in_bsp,
  MAX(CASE WHEN swf.status = 'NOT_CONVERTED' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_last_not_converted_in_bsp,
  MIN(CASE WHEN swf.status = 'PROCESSING' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_first_processing_photos_in_bsp,
  MAX(CASE WHEN swf.status = 'PROCESSING' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_last_processing_photos_in_bsp,
  MIN(CASE WHEN swf.status = 'SUSPENDED' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context ORDER BY swf.ts_start) AS ts_suspended_in_bsp,
  MIN(CASE WHEN swf.status = 'WAITING' THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context) AS ts_first_waiting,
  MIN(CASE WHEN swf.status = 'NOT_CONVERTED' AND swf.has_owner_info THEN swf.ts_start END)
      OVER (PARTITION BY swf.id_lead_3p, swf.business_context) AS ts_first_not_converted_w_owner,
  CASE
    WHEN swf.ts_start >= MIN(CASE WHEN swf.status IN ('REGISTERED', 'UNPUBLISHED') THEN swf.ts_start END)
        OVER (PARTITION BY swf.id_lead_3p, swf.business_context) THEN 'FIRST_LISTING'
    WHEN swf.ts_start >= MIN(CASE WHEN swf.status = 'PROCESSING' THEN swf.ts_start END)
        OVER (PARTITION BY swf.id_lead_3p, swf.business_context) THEN 'OPPORTUNITY'
    WHEN swf.ts_start >= MIN(CASE WHEN swf.status = 'NOT_CONVERTED' AND swf.has_owner_info THEN swf.ts_start END)
        OVER (PARTITION BY swf.id_lead_3p, swf.business_context) THEN 'QUALIFIED'
    WHEN swf.ts_start >= MIN(CASE WHEN swf.status = 'WAITING' THEN swf.ts_start END)
        OVER (PARTITION BY swf.id_lead_3p, swf.business_context) THEN 'PROSPECT'
    ELSE 'LEAD'
  END AS growth_status,
  CURRENT_TIMESTAMP() AS ts_load,
  FROM_UTC_TIMESTAMP(swf.ts_created, 'America/Sao_Paulo') AS ts_business_context_created,
  YEAR(swf.ts_start) AS year,
  MONTH(swf.ts_start) AS month,
  DAY(swf.ts_start) AS day
FROM
  status_with_flags AS swf
