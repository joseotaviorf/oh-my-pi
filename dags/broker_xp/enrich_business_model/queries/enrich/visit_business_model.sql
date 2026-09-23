WITH consolidated_visits AS (
  SELECT
    v.id AS id_visit,
    bm.id AS id_visit_business_model,
    v.id_house,
    COALESCE(bm.business_model, v.business_model) AS business_model,
    bm.ts_created AS ts_business_model_created,
    v.ts_created AS ts_visit_created,
    bm.ts_updated AS ts_business_model_updated,
    v.ts_updated AS ts_visit_updated
  FROM datalake_ebdb_clean.visit AS v
  LEFT JOIN datalake_ebdb_clean.visit_business_model AS bm
    ON v.id = bm.id_visit
)
SELECT
  id_visit,
  id_visit_business_model,
  id_house,
  sk_broker_supply,
  sk_broker_demand,
  id_company_supply,
  id_company_demand,
  partner_3p_supply,
  partner_3p_demand,
  business_model,
  is_3p_supply,
  is_3p_demand,
  is_3p_lead_gen,
  has_3p_access_control,
  ts_business_model_created,
  ts_visit_created,
  ts_business_model_updated,
  ts_visit_updated
FROM (
  SELECT
    cv.id_visit,
    cv.id_visit_business_model,
    cv.id_house,
    IF(cv.business_model LIKE '%3P_SUPPLY%', cbs.sk_broker, NULL) AS sk_broker_supply,
    IF(
      cv.business_model LIKE '%3P_DEMAND%' OR cv.business_model LIKE '%3P_LEAD_GEN%',
      cbd.sk_broker,
      NULL
    ) AS sk_broker_demand,
    -- id_company_* deprecated with datalake_company.company_sks (enrich_company); kept as NULL for schema compatibility.
    CAST(NULL AS BIGINT) AS id_company_supply,
    CAST(NULL AS BIGINT) AS id_company_demand,
    IF(cv.business_model LIKE '%3P_SUPPLY%', cbs.broker_name, NULL) AS partner_3p_supply,
    IF(
      cv.business_model LIKE '%3P_DEMAND%' OR cv.business_model LIKE '%3P_LEAD_GEN%',
      cbd.broker_name,
      NULL
    ) AS partner_3p_demand,
    cv.business_model,
    cv.business_model LIKE '%3P_SUPPLY%' AS is_3p_supply,
    cv.business_model LIKE '%3P_DEMAND%' AS is_3p_demand,
    cv.business_model LIKE '%3P_LEAD_GEN%' AS is_3p_lead_gen,
    cv.business_model LIKE '%3P%' AS has_3p_access_control,
    cv.ts_business_model_created,
    cv.ts_visit_created,
    cv.ts_business_model_updated,
    cv.ts_visit_updated,
    ROW_NUMBER() OVER (PARTITION BY vt.id_visit ORDER BY vt.ts_updated DESC) AS _w,
    vt.ts_updated
  FROM consolidated_visits AS cv
  LEFT JOIN datalake_ebdb_clean.visitor AS vt
    ON cv.id_visit = vt.id_visit AND vt.type = 'Agent'
  LEFT JOIN datalake_ebdb_listing.house AS h
    ON cv.id_house = h.id
  LEFT JOIN core_brokers.brokers AS cbs
    ON h.uuid_company = cbs.uuid_company
  LEFT JOIN core_brokers.brokers AS cbd
    ON vt.uuid_company = cbd.uuid_company
) AS _t
WHERE
  _w = 1