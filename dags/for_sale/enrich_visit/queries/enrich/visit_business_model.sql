WITH preferred_fixed_agent AS (
  SELECT
    pfa.id,
    pfa.id_agent_data AS id_agent,
    at.id_user AS id_user_agent,
    uvp.id_user AS id_visitor,
    at.dt_start,
    at.dt_end
  FROM
    datalake_ebdb_clean.preferred_fixed_agent AS pfa
  LEFT JOIN
    datalake_ebdb_clean.user_visit_preferences AS uvp
      ON pfa.id_user_visit_preferences = uvp.id
  INNER JOIN
    datalake_gsheets_clean.agents_3p_tqc AS at
      ON pfa.id_agent_data = at.id_agent
      AND DATE(pfa.ts_created) BETWEEN at.dt_start AND COALESCE(at.dt_end, CURRENT_DATE)
  WHERE
    pfa.origin = 'AGENT_LEAD_REFERRAL'
)
SELECT
  v.id AS id_visit,
  v.id_agent,
  v.id_visitor,
  CASE
    WHEN pfa.id IS NOT NULL AND v.business_model = 'BM_3P_LEAD_GEN_3P_SUPPLY' THEN 'BM_3P_DEMAND_3P_SUPPLY_6P'
    WHEN pfa.id IS NOT NULL AND v.business_model = 'BM_3P_LEAD_GEN_1P_SUPPLY' THEN 'BM_3P_DEMAND_1P_SUPPLY'
    ELSE v.business_model
  END AS business_model,
  v.ts_created,
  v.ts_updated
FROM
  datalake_ebdb_clean.visit AS v
LEFT JOIN
  preferred_fixed_agent AS pfa
    ON v.id_agent = pfa.id_user_agent
    AND v.id_visitor = pfa.id_visitor
    AND DATE(v.ts_created) BETWEEN pfa.dt_start AND COALESCE(pfa.dt_end, CURRENT_DATE)
