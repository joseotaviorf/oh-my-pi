SELECT
  log.row_instance_id,
  log.row_id AS user_id,
  log.timestamp,
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
WHERE log.timestamp >= '2025-09-24'
  AND meta.node_name IN ('FORA DOS FILTROS', 'EXPERIMENTO JAIMINHO FAKE', 'CONTROLE AUDIT')
  AND syc.op_type = 'added'
  AND syc.status = 'succeeded'
  AND syc.sync_id IN (2593283, 2593312, 2594586)
