WITH task_start AS (
  SELECT
    sk_task,
    sk_proposal,
    (ts_action - INTERVAL '3 hours') AS ts_task_started,
    ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY ts_action ASC) AS rank_ts
  FROM
    dw_crm.fact_credit_tasks AS crm
),

task_finish AS (
  SELECT
    crm.sk_task,
    crm.sk_proposal,
    crm.sk_assignee,
    crm.action_user_name,
    (crm.ts_action - INTERVAL '3 hours') AS ts_task_finished,
    ROW_NUMBER() OVER (PARTITION BY crm.sk_task ORDER BY crm.ts_action DESC) AS rank_tf
  FROM
    dw_crm.fact_credit_tasks AS crm
  LEFT JOIN
    datalake_credit_analysis.credit_analysis AS ca
      ON ca.id_proposal = crm.sk_proposal
  WHERE
    crm.action_type IN ('REALIZE')
    OR ca.reason IN ('AUTOMATIC_APPROVAL_WITH_MANUAL_INTERVENTION', 'AUTOMATIC_REJECTION_WITH_MANUAL_INTERVENTION', 'BYPASS_MANUAL_APPROVAL', 'BYPASS_MANUAL_REJECTION')
),

last_credit_analysis AS (
  SELECT
    id_proposal,
    MAX(ts_updated) AS ts_last_updated
  FROM
    datalake_sorting_hat_clean.credit_analysis
  WHERE
    type IS NOT NULL
  GROUP BY id_proposal
),

credit_analysis AS (
  SELECT
    ca.*
  FROM
    datalake_sorting_hat_clean.credit_analysis AS ca
  INNER JOIN
    last_credit_analysis AS lca
      ON ca.id_proposal = lca.id_proposal
      AND ca.ts_updated = lca.ts_last_updated
),

tasks AS (
  SELECT
    ts.sk_task,
    ts.sk_proposal,
    tf.sk_assignee,
    tf.action_user_name,
    ca.type,
    ts.ts_task_started,
    tf.ts_task_finished
  FROM
    task_start AS ts
  LEFT JOIN
    task_finish AS tf
      ON ts.sk_task = tf.sk_task
      AND ts.sk_proposal = tf.sk_proposal
  LEFT JOIN
    credit_analysis AS ca
      ON ts.sk_proposal = ca.id_proposal
  WHERE
    tf.ts_task_finished IS NOT NULL
    AND tf.rank_tf = 1
    AND ts.rank_ts = 1
)

SELECT DISTINCT
  sk_task,
  sk_proposal,
  sk_assignee,
  action_user_name,
  type AS documentation_policy,
  CAST((UNIX_TIMESTAMP(ts_task_finished) - UNIX_TIMESTAMP(ts_task_started)) / 60.0 AS FLOAT) AS task_total_min,
  CAST(FINTECHOPS_WORK_MIN_SLA(ts_task_started, ts_task_finished) AS FLOAT) AS task_working_min,
  ts_task_started,
  ts_task_finished,
  NOW() AS ts_load
FROM
  tasks
WHERE
  ts_task_started >= '2022-01-01'
