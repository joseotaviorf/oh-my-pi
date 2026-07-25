WITH tasks AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY ts_last_modified DESC) AS _w
    FROM datalake_salesforce_clean.task
  ) AS _t
  WHERE
    _w = 1
), salesforce_terminations AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_termination ORDER BY ts_last_modified DESC) AS _w
    FROM datalake_salesforce_clean.terminations
  ) AS _t
  WHERE
    _w = 1
), salesforce_cases AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_case ORDER BY ts_last_modified DESC) AS _w
    FROM datalake_salesforce_clean.cases
    WHERE
      NOT id_external IS NULL
  ) AS _t
  WHERE
    _w = 1
), salesforce_relisting AS (
  SELECT
    *,
    has_relisting_flow
  FROM (
    SELECT
      *,
      CASE
        WHEN is_relisting_eligible = TRUE AND is_early_relisting_active = FALSE
        THEN TRUE
        ELSE FALSE
      END AS has_relisting_flow,
      ROW_NUMBER() OVER (PARTITION BY id_relisting_context ORDER BY ts_last_modified DESC) AS _w
    FROM datalake_salesforce_clean.relisting_context
  ) AS _t
  WHERE
    _w = 1
), hefesto AS (
  SELECT
    id_contract,
    id_termination,
    worker_email
  FROM (
    SELECT
      id_contract,
      id_termination,
      worker_email,
      ROW_NUMBER() OVER (PARTITION BY id_termination ORDER BY ts_updated DESC) AS _w,
      ts_updated
    FROM datalake_hefesto.spoc_offboarding_contracts
  ) AS _t
  WHERE
    _w = 1
), main_query AS (
  SELECT DISTINCT
    t.id_task,
    t.id_contract,
    tm.id_external AS id_termination,
    CASE
      WHEN ft.ts_termination_request < CAST('2025-06-02' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND (
        ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL
      )
      THEN 'before_wave_6_lab_test'
      WHEN ft.ts_termination_request < CAST('2025-06-02' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND ft.is_spoc_control_group = TRUE
      THEN 'before_wave_6_lab_control'
      WHEN ft.ts_termination_request >= CAST('2025-05-22' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND (
        ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL
      )
      AND (
        dt.team = 'ROLLOUT' OR dt.team IS NULL
      )
      THEN 'rollout'
      WHEN ft.ts_termination_request BETWEEN CAST('2025-06-02' AS DATE) AND CAST('2025-07-29' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND (
        ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL
      )
      AND dt.team = 'LAB'
      THEN 'wave_6_lab_test'
      WHEN ft.ts_termination_request BETWEEN CAST('2025-07-30' AS DATE) AND CAST('{load_start_date}' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND (
        ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL
      )
      AND dt.team = 'LAB'
      THEN 'wave_6b_lab_test'
      WHEN ft.ts_termination_request BETWEEN CAST('2025-06-02' AS DATE) AND CAST('2025-07-29' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND ft.is_spoc_control_group = TRUE
      THEN 'wave_6_lab_control'
      WHEN ft.ts_termination_request BETWEEN CAST('2025-07-30' AS DATE) AND CAST('{load_start_date}' AS DATE)
      AND ft.is_spoc_contract = TRUE
      AND ft.is_spoc_control_group = TRUE
      THEN 'wave_6b_lab_control'
      ELSE NULL
    END AS spoc_class, /* sc.id_case, */
    tm.responsible_off_manager,
    h.worker_email AS responsible_off_manager_email,
    tm.high_value_contract,
    TO_DATE(CAST(ft.sk_termination_date AS STRING), 'yyyyMMdd') AS dt_termination,
    ft.ts_termination_request,
    ft.ts_termination_finished,
    dt.status AS termination_status,
    sc.case_status,
    sc.is_closed AS is_case_closed,
    t.subject,
    t.status,
    t.task_subtype,
    rc.has_relisting_flow,
    t.is_high_priority,
    t.is_deleted,
    t.is_closed,
    t.ts_created AS ts_task_created,
    t.ts_activity AS dt_task_expiration,
    t.ts_first_interaction AS dt_task_first_interaction_needed,
    t.ts_completed AS ts_task_completed,
    CASE
      WHEN COALESCE(
        DATE_TRUNC('DAY', t.ts_completed),
        DATE_TRUNC('DAY', DATE_ADD(CAST('{load_start_date}' AS DATE), -1))
      ) > t.ts_activity
      THEN TRUE
      ELSE FALSE
    END AS is_task_expired,
    CASE
      WHEN NOT t.ts_completed IS NULL
      THEN DATEDIFF(
        TO_DATE(DATE_TRUNC('DAY', t.ts_completed)),
        TO_DATE(DATE_TRUNC('DAY', t.ts_created))
      )
      ELSE NULL
    END AS task_leadtime
  FROM tasks AS t
  LEFT JOIN salesforce_terminations AS tm
    ON t.id_contract = tm.id_contract
  LEFT JOIN salesforce_cases AS sc
    ON sc.id_termination = tm.id_termination
  LEFT JOIN salesforce_relisting AS rc
    ON rc.id_termination = tm.id_termination
  LEFT JOIN dw_offboarding.fact_terminations AS ft
    ON tm.id_external = ft.sk_termination
  LEFT JOIN dw_offboarding.dim_termination AS dt
    ON dt.sk_termination = ft.sk_termination
  LEFT JOIN hefesto AS h
    ON sc.id_external = h.id_termination
  WHERE
    NOT tm.id_contract IS NULL
)
SELECT
  mq.id_task,
  mq.id_contract,
  mq.id_termination,
  mq.spoc_class,
  IF(
    mq.responsible_off_manager_email LIKE '%webhelp%',
    mq.responsible_off_manager_email,
    NULL
  ) AS spoc_agent_email,
  mq.high_value_contract,
  CAST(mq.dt_termination AS DATE) AS dt_termination,
  CAST(mq.ts_termination_request AS DATE) AS dt_termination_request,
  CAST(mq.ts_termination_finished AS DATE) AS dt_termination_finished,
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
  CAST(mq.ts_task_created AS DATE) AS dt_task_created,
  CAST(mq.dt_task_expiration AS DATE) AS dt_task_expiration,
  CAST(mq.dt_task_first_interaction_needed AS DATE) AS dt_task_first_interaction_needed,
  CAST(mq.ts_task_completed AS DATE) AS dt_task_completed,
  mq.is_task_expired,
  mq.task_leadtime,
  CASE
    WHEN mq.status IS NULL
    THEN NULL
    WHEN mq.status = 'Completed'
    AND CAST(mq.ts_task_completed AS DATE) <= CAST(mq.dt_task_expiration AS DATE)
    THEN 1
    WHEN mq.status = 'Completed'
    AND CAST(mq.ts_task_completed AS DATE) > CAST(mq.dt_task_expiration AS DATE)
    THEN 0
    ELSE NULL
  END AS sla_task,
  CASE
    WHEN mq.status IN ('Not Started', 'In Progress')
    AND CAST(mq.ts_task_completed AS DATE) IS NULL
    AND CAST(mq.dt_task_expiration AS DATE) < CAST(CAST('{load_start_date}' AS DATE) AS DATE)
    THEN 1
    WHEN mq.status IN ('Not Started', 'In Progress')
    AND CAST(mq.ts_task_completed AS DATE) IS NULL
    AND CAST(mq.dt_task_expiration AS DATE) >= CAST(CAST('{load_start_date}' AS DATE) AS DATE)
    THEN 0
    ELSE NULL
  END AS overdue_task,
  YEAR(TO_DATE(CURRENT_DATE)) AS year,
  MONTH(TO_DATE(CURRENT_DATE)) AS month,
  DAY(TO_DATE(CURRENT_DATE)) AS day,
  NOW() AS ts_load
FROM main_query AS mq
WHERE
  mq.ts_task_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '12' MONTH
  AND mq.ts_task_created >= CAST('2025-01-01' AS DATE)
