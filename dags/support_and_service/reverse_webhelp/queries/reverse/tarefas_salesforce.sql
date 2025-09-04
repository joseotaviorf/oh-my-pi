WITH
tasks AS (
SELECT
  *
FROM datalake_salesforce_clean.task
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY ts_last_modified DESC) = 1
),

salesforce_terminations AS (
SELECT
  *
FROM datalake_salesforce_clean.terminations
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_termination ORDER BY ts_last_modified DESC) = 1
),

salesforce_cases AS (
SELECT
  *
FROM datalake_salesforce_clean.cases
WHERE id_external IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_case ORDER BY ts_last_modified DESC) = 1
),

salesforce_relisting AS (
SELECT
  *,
  CASE WHEN is_relisting_eligible = TRUE AND is_early_relisting_active = FALSE THEN TRUE
    ELSE FALSE
  END has_relisting_flow
FROM datalake_salesforce_clean.relisting_context
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_relisting_context ORDER BY ts_last_modified DESC) = 1
),

hefesto AS (
SELECT
  id_contract,
  id_termination,
  worker_email
FROM datalake_hefesto.spoc_offboarding_contracts
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_termination ORDER BY ts_updated DESC) = 1
),

main_query AS (

SELECT DISTINCT
  t.id_task,
  t.id_contract,
  tm.id_external id_termination,
  --sc.id_case,
CASE WHEN ft.ts_termination_request < DATE('2025-06-02') AND ft.is_spoc_contract = TRUE AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL) THEN 'before_wave_6_lab_test'
     WHEN ft.ts_termination_request < DATE('2025-06-02') AND ft.is_spoc_contract = TRUE AND ft.is_spoc_control_group = TRUE THEN 'before_wave_6_lab_control'
     WHEN ft.ts_termination_request >= DATE('2025-05-22') AND ft.is_spoc_contract = TRUE AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL) AND (dt.team = 'ROLLOUT' OR dt.team IS NULL) THEN 'rollout'
     WHEN ft.ts_termination_request BETWEEN DATE('2025-06-02') AND DATE('2025-07-29') AND ft.is_spoc_contract = TRUE AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL) AND dt.team = 'LAB' THEN 'wave_6_lab_test'
     WHEN ft.ts_termination_request BETWEEN DATE('2025-07-30') AND DATE('{load_start_date}') AND ft.is_spoc_contract = TRUE AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL) AND dt.team = 'LAB' THEN 'wave_6b_lab_test'
     WHEN ft.ts_termination_request BETWEEN DATE('2025-06-02') AND DATE('2025-07-29') AND ft.is_spoc_contract = TRUE AND ft.is_spoc_control_group = TRUE THEN 'wave_6_lab_control'
     WHEN ft.ts_termination_request BETWEEN DATE('2025-07-30') AND DATE('{load_start_date}') AND ft.is_spoc_contract = TRUE AND ft.is_spoc_control_group = TRUE THEN 'wave_6b_lab_control'
     ELSE NULL
  END spoc_class,
  tm.responsible_off_manager,
  h.worker_email responsible_off_manager_email,
  tm.high_value_contract,
  TO_DATE(CAST(ft.sk_termination_date AS VARCHAR(20)), 'yyyyMMdd') dt_termination,
  ft.ts_termination_request,
  ft.ts_termination_finished,
  dt.status termination_status,
  sc.case_status,
  sc.is_closed is_case_closed,
  t.subject,
  t.status,
  t.task_subtype,
  rc.has_relisting_flow,
  t.is_high_priority,
  t.is_deleted,
  t.is_closed,
  t.ts_created ts_task_created,
  t.ts_activity dt_task_expiration,
  t.ts_first_interaction dt_task_first_interaction_needed,
  t.ts_completed ts_task_completed,
  CASE WHEN COALESCE(DATE_TRUNC('day', t.ts_completed), DATE_TRUNC('day', DATE_ADD(DAY, -1, DATE('{load_start_date}')))) > t.ts_activity THEN TRUE
   ELSE FALSE
  END is_task_expired,
  CASE WHEN t.ts_completed IS NOT NULL THEN DATE_DIFF(day, DATE_TRUNC('day', t.ts_created), date_trunc('day', t.ts_completed))
   ELSE NULL
  END task_leadtime

FROM tasks t
LEFT JOIN salesforce_terminations tm
  ON t.id_contract = tm.id_contract
LEFT JOIN salesforce_cases sc
  ON sc.id_termination = tm.id_termination
LEFT JOIN salesforce_relisting rc
  ON rc.id_termination = tm.id_termination
LEFT JOIN dw_offboarding.fact_terminations ft
  ON tm.id_external = ft.sk_termination
LEFT JOIN dw_offboarding.dim_termination dt
  ON dt.sk_termination = ft.sk_termination
LEFT JOIN hefesto h
  ON sc.id_external = h.id_termination

WHERE tm.id_contract IS NOT NULL

)

SELECT
  mq.id_task,
  mq.id_contract,
  mq.id_termination,
  mq.spoc_class,
  IF(mq.responsible_off_manager_email LIKE '%webhelp%', mq.responsible_off_manager_email, NULL) spoc_agent_email,
  mq.high_value_contract,
  DATE(mq.dt_termination) dt_termination,
  DATE(mq.ts_termination_request) ts_termination_request,
  DATE(mq.ts_termination_finished) ts_termination_finished,
  mq.termination_status,
  mq.case_status,
  mq.is_case_closed,
  mq.subject,
  mq.status,
  mq.task_subtype,
  mq.has_relisting_flow,
  mq.is_high_priority,
  mq.is_deleted,
  mq.is_closed,
  DATE(mq.ts_task_created) dt_task_created,
  DATE(mq.dt_task_expiration) dt_task_expiration,
  DATE(mq.dt_task_first_interaction_needed) dt_task_first_interaction_needed,
  DATE(mq.ts_task_completed) dt_task_completed,
  mq.is_task_expired,
  mq.task_leadtime,
  CASE WHEN mq.status IS NULL THEN NULL
    WHEN mq.status = 'Completed' AND DATE(mq.ts_task_completed) <= DATE(mq.dt_task_expiration) THEN 1
    WHEN mq.status = 'Completed' AND DATE(mq.ts_task_completed) > DATE(mq.dt_task_expiration) THEN 0
    ELSE NULL
  END sla_task,
  CASE WHEN mq.status IN ('Not Started', 'In Progress') AND DATE(mq.ts_task_completed) IS NULL AND DATE(mq.dt_task_expiration) < DATE(DATE('{load_start_date}')) THEN 1
    WHEN mq.status IN ('Not Started', 'In Progress') AND DATE(mq.ts_task_completed) IS NULL AND DATE(mq.dt_task_expiration) >= DATE(DATE('{load_start_date}')) THEN 0
    ELSE NULL
  END overdue_task,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load

FROM main_query mq
WHERE mq.ts_task_created >= DATE('{load_start_date}') - INTERVAL '12' MONTH 
AND mq.ts_task_created >= DATE('2025-01-01')
