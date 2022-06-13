WITH task_start AS (
  SELECT
    sk_task,
    sk_proposal,
    MIN(ts_action - INTERVAL '3 hours') AS ts_task_started
  FROM
    dw_crm.fact_credit_tasks AS crm 
  WHERE
    action_type = 'CREATE'
  GROUP BY 1, 2
),

task_finish AS (
  SELECT
    sk_task,
    sk_proposal,
    action_user_name,
    MIN(ts_action - INTERVAL '3 hours') AS ts_task_finished
  FROM
    dw_crm.fact_credit_tasks AS crm 
  WHERE
    action_type = 'REALIZE'
  GROUP BY 1, 2, 3
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
    tf.action_user_name,
    ca.type,
    ts.ts_task_started,
    tf.ts_task_finished
  FROM
    task_start AS ts
  LEFT JOIN
    task_finish AS tf
      ON ts.sk_task = tf.sk_task
  LEFT JOIN
    credit_analysis AS ca
      ON ts.sk_proposal = ca.id_proposal
  WHERE
    tf.ts_task_finished IS NOT NULL
)

SELECT 
  sk_task,
  sk_proposal,
  action_user_name,
  type AS documentation_policy,
  CAST(FINTECHOPS_WORK_MIN_SLA(ts_task_started, ts_task_finished) AS FLOAT) AS task_working_min,
  ts_task_started,
  ts_task_finished
FROM
  tasks 
WHERE
  ts_task_started >= '2022-01-01'
