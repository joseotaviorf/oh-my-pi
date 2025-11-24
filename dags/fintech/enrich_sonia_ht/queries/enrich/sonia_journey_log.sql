WITH hightouch_all_data AS (
  SELECT
    log.row_instance_id,
    log.row_id,
    COALESCE(get_json_object(syc.fields, '$.id_user'), log.row_id) AS user_id,
    log.timestamp,
    runs.started_at,
    runs.finished_at,
    syc.sync_id,
    syc.sync_run_id,
    CASE
      WHEN meta.node_name = 'FORA DOS FILTROS' THEN 'Out of Experiment'
      WHEN meta.node_name = 'D+1 Jaiminho' THEN 'Test'
      WHEN meta.node_name = 'CONTROLE AUDIT' THEN 'Control'
      WHEN meta.node_name = 'D+3 Jaiminho' THEN 'FUP D+3'
      WHEN meta.node_name = 'D+5 Jaiminho' THEN 'FUP D+5'
    END AS group_name,
    get_json_object(syc.fields, '$.id_proposal') AS proposal_id,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_bypass') AS BOOLEAN), FALSE) AS is_bypass,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_credit_passport') AS BOOLEAN), FALSE) AS is_credit_passport,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_free_guarantee_offered') AS BOOLEAN), TRUE) AS is_free_guarantee_offered,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_light_approval') AS BOOLEAN), TRUE) AS is_light_approval,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_only_one_active_offer') AS BOOLEAN), TRUE) AS is_only_one_active_offer,
    COALESCE(CAST(get_json_object(syc.fields, '$.is_single_tenant') AS BOOLEAN), TRUE) AS is_single_tenant,
    CONCAT(get_json_object(syc.fields, '$.id_proposal'), COALESCE(CAST(get_json_object(syc.fields, '$.is_only_one_active_offer') AS BOOLEAN), TRUE)) AS proposal_active_offer
  FROM hightouch_planner.journey_log_93d2e2b5d82c486db22aa5209dddf354 AS log
  LEFT JOIN hightouch_planner.journey_metadata_93d2e2b5d82c486db22aa5209dddf354 AS meta
    ON log.to_node_id = meta.node_id
  INNER JOIN hightouch_audit.sync_changelog AS syc
    ON log.row_instance_id = syc.row_id
  INNER JOIN hightouch_audit.sync_runs AS runs
    ON syc.sync_run_id = runs.sync_run_id
  WHERE log.timestamp >= '2025-09-24'
    AND meta.node_name IN ('FORA DOS FILTROS', 'D+1 Jaiminho', 'CONTROLE AUDIT', 'D+3 Jaiminho', 'D+5 Jaiminho')
    AND syc.op_type = 'added'
    AND syc.status = 'succeeded'
    AND syc.sync_id IN (2593283, 2593312, 2594586)
    AND runs.sync_id IN (2593283, 2593312, 2594586)
),
fup_d3_data AS (
  SELECT
    proposal_id,
    TRUE AS is_fup_d3,
    MIN(started_at) AS started_at_fup_d3,
    MIN(finished_at) AS finished_at_fup_d3
  FROM hightouch_all_data
  WHERE group_name = 'FUP D+3'
  GROUP BY 1, 2
),
fup_d5_data AS (
  SELECT
    proposal_id,
    TRUE AS is_fup_d5,
    MIN(started_at) AS started_at_fup_d5,
    MIN(finished_at) AS finished_at_fup_d5
  FROM hightouch_all_data
  WHERE group_name = 'FUP D+5'
  GROUP BY 1, 2
),
fup_data AS (
  SELECT
    d3.*,
    d5.is_fup_d5,
    d5.started_at_fup_d5,
    d5.finished_at_fup_d5
  FROM fup_d3_data AS d3
  LEFT JOIN fup_d5_data AS d5
    ON d3.proposal_id = d5.proposal_id
),
hightouch_data AS (
  SELECT
    hd.*,
    COALESCE(fd.is_fup_d3, FALSE) AS is_fup_d3,
    fd.started_at_fup_d3,
    fd.finished_at_fup_d3,
    COALESCE(fd.is_fup_d5, FALSE) AS is_fup_d5,
    fd.started_at_fup_d5,
    fd.finished_at_fup_d5
  FROM hightouch_all_data AS hd
  LEFT JOIN fup_data AS fd
    ON hd.proposal_id = fd.proposal_id
  WHERE hd.group_name NOT IN ('FUP D+3', 'FUP D+5')
),
rn_count AS (
  SELECT
    *,
    IF(is_bypass = FALSE AND is_credit_passport = FALSE AND is_free_guarantee_offered AND is_light_approval AND is_only_one_active_offer AND is_single_tenant, TRUE, FALSE) AS is_poc_eligible,
    ROW_NUMBER() OVER (PARTITION BY proposal_active_offer ORDER BY IF(group_name = 'Out of Experiment', 1, IF(group_name = 'Test', 2, 3))) AS rn_latest
  FROM hightouch_data
),
groups_agg AS (
  SELECT
    proposal_active_offer,
    ARRAY_JOIN(ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(group_name))), ', ') AS all_groups
  FROM hightouch_data
  GROUP BY proposal_active_offer
)
SELECT
  rc.row_instance_id,
  rc.row_id,
  rc.user_id,
  rc.proposal_id,
  rc.timestamp,
  rc.started_at,
  rc.finished_at,
  rc.sync_id,
  rc.sync_run_id,
  CASE
    WHEN ga.all_groups IN ('Out of Experiment', 'Control', 'Test') THEN ga.all_groups
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Test%' AND rc.is_poc_eligible THEN 'Test'
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Control%' AND rc.is_poc_eligible THEN 'Control'
    WHEN ga.all_groups LIKE '%Out of Experiment%' THEN 'Error - Out of Experiment'
    WHEN ga.all_groups LIKE '%Test%' THEN 'Test'
    WHEN ga.all_groups LIKE '%Control%' THEN 'Control'
  END AS group_name,
  CASE
    WHEN ga.all_groups IN ('Out of Experiment', 'Control', 'Test') THEN ga.all_groups
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Test%' AND rc.is_poc_eligible THEN 'Error - Assigned Test and Out of Experiment, Really Test'
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Control%' AND rc.is_poc_eligible THEN 'Error - Assigned Control and Out of Experiment, Really Control'
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Test%' THEN 'Error - Assigned Test and Out of Experiment, Really Out'
    WHEN ga.all_groups LIKE '%Out of Experiment%' AND ga.all_groups LIKE '%Control%' THEN 'Error - Assigned Control and Out of Experiment, Really Out'
    WHEN ga.all_groups LIKE '%Test%' THEN 'Error - Assigned Control and Test'
  END AS group_name_full,
  rc.is_fup_d3,
  rc.started_at_fup_d3,
  rc.finished_at_fup_d3,
  rc.is_fup_d5,
  rc.started_at_fup_d5,
  rc.finished_at_fup_d5,
  rc.is_bypass,
  rc.is_credit_passport,
  rc.is_free_guarantee_offered,
  rc.is_light_approval,
  rc.is_only_one_active_offer,
  rc.is_single_tenant,
  rc.proposal_active_offer
FROM rn_count AS rc
JOIN groups_agg AS ga
  ON rc.proposal_active_offer = ga.proposal_active_offer
WHERE rc.rn_latest = 1
