WITH csat AS (
  SELECT
    id_agent,
    type,
    SUM(CASE WHEN csat_score >= 4 THEN 1 ELSE 0 END) AS sum_csat_satisfied_score,
    SUM(CASE WHEN csat_score < 3 THEN 1 ELSE 0 END) AS sum_csat_dissatisfied_score,
    SUM(CAST(is_solved = TRUE AS SMALLINT)) AS total_tickets_resolution,
    SUM(CAST(is_solved IS NOT NULL AS SMALLINT)) AS total_tickets_answered_resolution,
    SUM(CAST(csat_score IS NOT NULL AS SMALLINT)) AS total_tickets_with_csat_score,
    DATE(ts_csat_answer) AS dt_metric_reference
  FROM
    datalake_customer_demand.base_tasks
  WHERE
    csat_score IS NOT NULL
    OR is_solved IS NOT NULL
  GROUP BY 
    id_agent, 
    type, 
    DATE(ts_csat_answer)
)
SELECT
  id_agent,
  type,
  sum_csat_satisfied_score,
  sum_csat_dissatisfied_score,
  total_tickets_resolution,
  total_tickets_answered_resolution,
  total_tickets_with_csat_score,
  dt_metric_reference
FROM
  csat