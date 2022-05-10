WITH demand_metrics AS (
  SELECT
    id_agent,
    closed_demand,
    solved_demand,
    tickets_solved_in_time,
    tickets_not_solved_in_time,
    dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics
  WHERE
    dt_metric_reference = DATE('{year}-{month}-{day}')
    AND NULLIF(id_agent, -1) IS NOT NULL
),
quality_metrics AS (
  SELECT 
    id_agent,
    sum_csat_satisfied_score,
    sum_csat_dissatisfied_score,
    total_tickets_resolution,
    total_tickets_answered_resolution,
    total_tickets_with_csat_score,
    dt_metric_reference
  FROM
    datalake_customer_demand.quality_metrics
  WHERE
    dt_metric_reference = DATE('{year}-{month}-{day}')
    AND NULLIF(id_agent, -1) IS NOT NULL
)
SELECT
  COALESCE(dm.id_agent, qm.id_agent) AS id_agent,
  sad.department,
  SUM(COALESCE(closed_demand, 0)) AS closed_demand,
  SUM(COALESCE(solved_demand, 0)) AS solved_demand,
  SUM(COALESCE(tickets_solved_in_time, 0)) AS tickets_solved_in_time,
  SUM(COALESCE(tickets_not_solved_in_time, 0)) AS tickets_not_solved_in_time,
  SUM(COALESCE(sum_csat_satisfied_score,0)) AS sum_csat_satisfied_score,
  SUM(COALESCE(sum_csat_dissatisfied_score,0)) AS sum_csat_dissatisfied_score,
  SUM(COALESCE(total_tickets_resolution,0)) AS total_tickets_resolution,
  SUM(COALESCE(total_tickets_answered_resolution,0)) AS total_tickets_answered_resolution,
  SUM(COALESCE(total_tickets_with_csat_score,0)) AS total_tickets_with_csat_score,
  COALESCE(dm.dt_metric_reference, qm.dt_metric_reference) AS dt_metric_reference,
  YEAR(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference)) AS year,
  MONTH(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference)) AS month,
  DAY(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference)) AS day
FROM
  demand_metrics dm
FULL OUTER JOIN
  quality_metrics qm
    ON dm.id_agent = qm.id_agent
    AND dm.dt_metric_reference = qm.dt_metric_reference
JOIN
  datalake_gsheets_clean.support_agents_department sad
    ON COALESCE(dm.id_agent, qm.id_agent) = sad.id_agent
    AND COALESCE(dm.dt_metric_reference, qm.dt_metric_reference) BETWEEN sad.dt_start AND COALESCE(sad.dt_end, NOW())
GROUP BY 
  COALESCE(dm.id_agent, qm.id_agent),
  sad.department,
  COALESCE(dm.dt_metric_reference, qm.dt_metric_reference)