WITH consolidated_visits AS (
  SELECT
    v.id AS id_visit,
    bm.id AS id_visit_business_model,
    COALESCE(bm.business_model, v.business_model) AS business_model,
    bm.ts_created AS ts_business_model_created,
    v.ts_created AS ts_visit_created,
    bm.ts_updated AS ts_business_model_updated,
    v.ts_updated AS ts_visit_updated
  FROM
    datalake_ebdb_clean.visit AS v
  LEFT JOIN
    datalake_ebdb_clean.visit_business_model AS bm
      ON v.id = bm.id_visit
)
SELECT
  cv.id_visit,
  cv.id_visit_business_model,
  c.sk_company AS id_company_demand,
  vt.uuid_company,
  cv.business_model,
  c.company_name AS partner_3p_demand,
  cv.business_model LIKE '%3P_SUPPLY%' AS is_3p_supply,
  cv.business_model LIKE '%3P_DEMAND%' AS is_3p_demand,
  cv.business_model LIKE '%3P_LEAD_GEN%' AS is_3p_lead_gen,
  cv.business_model LIKE '%3P%' AS has_3p_access_control,
  cv.ts_business_model_created,
  cv.ts_visit_created,
  cv.ts_business_model_updated,
  cv.ts_visit_updated
FROM
  consolidated_visits AS cv
LEFT JOIN
  datalake_ebdb_clean.visitor AS vt
    ON cv.id_visit = vt.id_visit
      AND vt.type = 'Agent'
LEFT JOIN
  datalake_company.company_sks AS c
    ON vt.uuid_company = c.uuid_company
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY vt.id_visit ORDER BY vt.ts_updated DESC) = 1