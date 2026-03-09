WITH
pathway_totals AS (
  SELECT
    id_plan,
    COUNT(*) AS pathway_total
  FROM
    datalake_learning.plan_pathways
  GROUP BY
    id_plan
),
pathway_completed_users AS (
  SELECT
    ac.id_user,
    pp.id_plan,
    ac.id_pathway,
    ac.dt_completion
  FROM
    datalake_learning.all_completions AS ac
  INNER JOIN
    datalake_learning.plan_pathways AS pp
    ON pp.id_pathway = ac.id_learning_object
  WHERE
    ac.learning_object_type = 'Pathway'
    AND ac.completed_required = ac.content_required
    AND ac.content_required > 0
),
user_plan_agg AS (
  SELECT
    id_user,
    id_plan,
    COUNT(*) AS completed_pathways,
    MIN(dt_completion) AS dt_completion
  FROM
    pathway_completed_users
  GROUP BY
    id_user,
    id_plan
),
all_users AS (
  SELECT
    id AS id_user
  FROM
    datalake_degreed_clean.users
),
all_plans AS (
  SELECT DISTINCT
    id_plan
  FROM
    datalake_learning.plan_pathways
),
base AS (
  SELECT
    u.id_user,
    p.id_plan
  FROM
    all_users AS u
  CROSS JOIN
    all_plans AS p
)
SELECT
  b.id_user,
  b.id_plan,
  pt.pathway_total,
  COALESCE(upa.completed_pathways, 0) AS completed_pathways,
  COALESCE(upa.completed_pathways, 0) >= 1 AS is_plan_completed,
  upa.dt_completion AS dt_completion,
  NOW() AS ts_load
FROM
  base AS b
LEFT JOIN
  pathway_totals AS pt
  ON pt.id_plan = b.id_plan
LEFT JOIN
  user_plan_agg AS upa
  ON upa.id_user = b.id_user
  AND upa.id_plan = b.id_plan
