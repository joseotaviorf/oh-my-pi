WITH pfa_history AS (
  SELECT
    pfa.id_pfa_history,
    pfa.id_visitor,
    pfa.id_user_agent,
    pfa.origin,
    pfa.is_enabled,
    pfa.origin = 'VISIT_SCHEDULED' AS is_visit_scheduled_pfa_origin,
    pfa.ts_started,
    pfa.ts_ended
  FROM
    datalake_visit.preferred_fixed_agent_history AS pfa
  WHERE
    pfa.business_context = 'SALE'
),
visit_business_rules AS (
  SELECT
    v.id AS id_visit,
    pfa.id_pfa_history,
    pfa.origin,
    atqc.id_user = pfa.id_user_agent AS is_pfa_tqc_3p_agent,
    pfa.is_visit_scheduled_pfa_origin,
    atqc.id_user IS NOT NULL AS is_visit_tqc_3p_agent,
    pfa.id_pfa_history IS NOT NULL AS has_pfa
  FROM
    datalake_ebdb_clean.visit AS v
  LEFT JOIN
    datalake_gsheets_clean.agents_3p_tqc AS atqc
      ON v.id_agent = atqc.id_user
      AND DATE(v.ts_created) BETWEEN atqc.dt_start AND COALESCE(atqc.dt_end, CURRENT_DATE)
  LEFT JOIN
    pfa_history AS pfa
      ON v.id_visitor = pfa.id_visitor
      AND v.ts_created >= pfa.ts_started
      AND v.ts_created < COALESCE(pfa.ts_ended, CURRENT_DATE)
)
SELECT
  vbr.id_visit,
  v.id_agent,
  vbr.id_pfa_history,
  v.id_visitor,
  CASE
    -- Agent in TQC 3P PoC, PFA from same agent and PFA origin not VISIT_SCHEDULED
    WHEN (vbr.is_visit_tqc_3p_agent AND vbr.is_pfa_tqc_3p_agent AND NOT(vbr.is_visit_scheduled_pfa_origin)) AND v.business_model = 'BM_3P_LEAD_GEN_3P_SUPPLY' THEN 'BM_3P_DEMAND_3P_SUPPLY_6P'
    WHEN (vbr.is_visit_tqc_3p_agent AND vbr.is_pfa_tqc_3p_agent AND NOT(vbr.is_visit_scheduled_pfa_origin)) AND v.business_model = 'BM_3P_LEAD_GEN_1P_SUPPLY' THEN 'BM_3P_DEMAND_1P_SUPPLY'
    -- Agent in TQC 3P PoC, PFA from another agent
    WHEN (vbr.is_visit_tqc_3p_agent AND NOT(vbr.is_pfa_tqc_3p_agent)) AND v.business_model = 'BM_3P_LEAD_GEN_3P_SUPPLY' THEN 'BM_3P_DEMAND_3P_SUPPLY_6P'
    WHEN (vbr.is_visit_tqc_3p_agent AND NOT(vbr.is_pfa_tqc_3p_agent)) AND v.business_model = 'BM_3P_LEAD_GEN_1P_SUPPLY' THEN 'BM_3P_DEMAND_1P_SUPPLY'
    -- Agent in TQC 3P PoC and visitor without PFA
    WHEN (vbr.is_visit_tqc_3p_agent AND NOT(vbr.has_pfa)) AND v.business_model = 'BM_3P_LEAD_GEN_3P_SUPPLY' THEN 'BM_3P_DEMAND_3P_SUPPLY_6P'
    WHEN (vbr.is_visit_tqc_3p_agent AND NOT(vbr.has_pfa)) AND v.business_model = 'BM_3P_LEAD_GEN_1P_SUPPLY' THEN 'BM_3P_DEMAND_1P_SUPPLY'
    -- Agents not in TQC 3P
    ELSE v.business_model
  END AS business_model,
  vbr.is_pfa_tqc_3p_agent,
  vbr.is_visit_scheduled_pfa_origin,
  vbr.is_visit_tqc_3p_agent,
  vbr.has_pfa,
  v.ts_created,
  v.ts_updated
FROM
  visit_business_rules AS vbr
LEFT JOIN
  datalake_ebdb_clean.visit AS v
  ON vbr.id_visit = v.id