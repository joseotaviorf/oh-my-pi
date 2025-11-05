SELECT
  bm.id,
  vt.id_booking,
  bm.id_visit,
  vt.uuid_company,
  bm.business_model,
  bm.business_model LIKE '%3P_SUPPLY%' AS is_3p_supply,
  bm.business_model LIKE '%3P_DEMAND%' AS is_3p_demand,
  bm.business_model LIKE '%3P_LEAD_GEN%' AS is_3p_lead_gen,
  bm.business_model LIKE '%3P%' AS has_3p_access_control,
  bm.ts_created,
  bm.ts_updated
FROM
  datalake_ebdb_clean.visit_business_model AS bm
LEFT JOIN
  datalake_ebdb_clean.visitor AS vt
    ON bm.id_visit = vt.id_visit
      AND vt.type = 'Agent'