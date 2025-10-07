WITH hightouch_data as (
SELECT
  log.row_instance_id,
  log.row_id AS user_id,
  log.timestamp,
  runs.started_at,
  runs.finished_at,
  syc.sync_id,
  syc.sync_run_id,
  CASE
    WHEN meta.node_name = 'FORA DOS FILTROS' THEN 'Out of Experiment'
    WHEN meta.node_name = 'EXPERIMENTO JAIMINHO FAKE' THEN 'Test'
    WHEN meta.node_name = 'CONTROLE AUDIT' THEN 'Control'
   END AS group_name,
  get_json_object(syc.fields, '$.id_proposal') AS proposal_id,
  get_json_object(syc.fields, '$.is_bypass') AS is_bypass,
  get_json_object(syc.fields, '$.is_credit_passport') AS is_credit_passport,
  get_json_object(syc.fields, '$.is_free_guarantee_offered') AS is_free_guarantee_offered,
  get_json_object(syc.fields, '$.is_light_approval') AS is_light_approval,
  get_json_object(syc.fields, '$.is_only_one_active_offer') AS is_only_one_active_offer,
  get_json_object(syc.fields, '$.is_single_tenant') AS is_single_tenant
FROM hightouch_planner.journey_log_93d2e2b5d82c486db22aa5209dddf354 AS log
LEFT JOIN hightouch_planner.journey_metadata_93d2e2b5d82c486db22aa5209dddf354 AS meta
  ON log.to_node_id = meta.node_id
INNER JOIN hightouch_audit.sync_changelog AS syc
  ON log.row_instance_id = syc.row_id
INNER JOIN hightouch_audit.sync_runs AS runs
  ON syc.sync_run_id = runs.sync_run_id
WHERE log.timestamp >= '2025-09-24'
  AND meta.node_name IN ('FORA DOS FILTROS', 'EXPERIMENTO JAIMINHO FAKE', 'CONTROLE AUDIT')
  AND syc.op_type = 'added'
  AND syc.status = 'succeeded'
  AND syc.sync_id IN (2593283, 2593312, 2594586)
  AND runs.sync_id IN (2593283, 2593312, 2594586)
),
rn_count AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY proposal_id ORDER BY IF(group_name = 'Out of Experiment', 1, IF(group_name = 'Test', 2, 3))) AS rn_latest
  FROM hightouch_data
),
groups_agg AS (
  SELECT
    proposal_id,
    ARRAY_JOIN(ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(group_name))), ', ') AS all_groups
  FROM hightouch_data
  GROUP BY proposal_id
)
SELECT
  rc.row_instance_id,
  rc.user_id,
  rc.proposal_id,
  rc.timestamp,
  rc.started_at,
  rc.finished_at,
  rc.sync_id,
  rc.sync_run_id,
  CASE
    WHEN ga.all_groups IN ('Out of Experiment', 'Control', 'Test') THEN all_groups
    WHEN ga.all_groups LIKE '%Out of Experiment%' THEN 'Error - Out of Experiment'
    WHEN ga.all_groups LIKE '%Test%' THEN 'Test'
    WHEN ga.all_groups LIKE '%Control%' THEN 'Control'
  END AS group_name,
  CASE
    WHEN ga.all_groups IN ('Out of Experiment', 'Control', 'Test') THEN all_groups
    WHEN ga.all_groups LIKE '%Out of Experiment%' THEN 'Error - Out of Experiment'
    WHEN ga.all_groups LIKE '%Test%' THEN 'Error - Test'
    WHEN ga.all_groups LIKE '%Control%' THEN 'Error - Control'
  END AS group_name_full,
  COALESCE(CAST(rc.is_bypass AS BOOLEAN), FALSE) AS is_bypass,
  COALESCE(CAST(rc.is_credit_passport AS BOOLEAN), FALSE) AS is_credit_passport,
  COALESCE(CAST(rc.is_free_guarantee_offered AS BOOLEAN), TRUE) AS is_free_guarantee_offered,
  COALESCE(CAST(rc.is_light_approval AS BOOLEAN), TRUE) AS is_light_approval,
  COALESCE(CAST(rc.is_only_one_active_offer AS BOOLEAN), TRUE) AS is_only_one_active_offer,
  COALESCE(CAST(rc.is_single_tenant AS BOOLEAN), TRUE) AS is_single_tenant
FROM rn_count AS rc
JOIN groups_agg AS ga
  ON rc.proposal_id = ga.proposal_id
WHERE rc.rn_latest = 1
