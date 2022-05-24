WITH demand_metrics AS (
  SELECT
    id_agent,
    SUM(COALESCE(closed_demand, 0)) AS closed_demand,
    SUM(COALESCE(solved_demand, 0)) AS solved_demand,
    SUM(COALESCE(tickets_solved_in_time, 0)) AS tickets_solved_in_time,
    SUM(COALESCE(tickets_not_solved_in_time, 0)) AS tickets_not_solved_in_time,
    dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics
  WHERE
    dt_metric_reference BETWEEN (DATE('{year}-{month}-{day}') - INTERVAL 1 DAYS) AND DATE('{year}-{month}-{day}')
    AND NULLIF(id_agent, -1) IS NOT NULL
  GROUP BY id_agent, dt_metric_reference
),
quality_metrics AS (
  SELECT 
    id_agent,
    SUM(COALESCE(sum_csat_satisfied_score, 0)) AS sum_csat_satisfied_score,
    SUM(COALESCE(sum_csat_dissatisfied_score, 0)) AS sum_csat_dissatisfied_score,
    SUM(COALESCE(total_tickets_resolution,0)) AS total_tickets_resolution,
    SUM(COALESCE(total_tickets_answered_resolution, 0)) AS total_tickets_answered_resolution,
    SUM(COALESCE(total_tickets_with_csat_score, 0)) AS total_tickets_with_csat_score,
    dt_metric_reference
  FROM
    datalake_customer_demand.quality_metrics
  WHERE
    dt_metric_reference BETWEEN (DATE('{year}-{month}-{day}') - INTERVAL 1 DAYS) AND DATE('{year}-{month}-{day}')
    AND NULLIF(id_agent, -1) IS NOT NULL
  GROUP BY id_agent, dt_metric_reference
),
ra_metrics AS (
  SELECT
    id_agent,
    ra_score_sum,
    ra_would_do_business_again,
    ra_solved_tickets,
    ra_total_tickets_rated,
    dt_metric_reference
  FROM
    datalake_customer_demand.ra_metrics
  WHERE
    dt_metric_reference BETWEEN (DATE('{year}-{month}-{day}') - INTERVAL 1 DAYS) AND DATE('{year}-{month}-{day}')
)
SELECT
  COALESCE(dm.id_agent, qm.id_agent, rm.id_agent) AS id_agent,
  sad.department,
  SUM(closed_demand) AS closed_demand,
  SUM(solved_demand) AS solved_demand,
  SUM(tickets_solved_in_time) AS tickets_solved_in_time,
  SUM(tickets_not_solved_in_time) AS tickets_not_solved_in_time,
  SUM(sum_csat_satisfied_score) AS sum_csat_satisfied_score,
  SUM(sum_csat_dissatisfied_score) AS sum_csat_dissatisfied_score,
  SUM(total_tickets_resolution) AS total_tickets_resolution,
  SUM(total_tickets_answered_resolution) AS total_tickets_answered_resolution,
  SUM(total_tickets_with_csat_score) AS total_tickets_with_csat_score,
  SUM(ra_score_sum) AS ra_score_sum,
  SUM(ra_would_do_business_again) AS ra_would_do_business_again,
  SUM(ra_solved_tickets) AS ra_solved_tickets,
  SUM(ra_total_tickets_rated) AS ra_total_tickets_rated,
  FLOOR(MAX(MONTHS_BETWEEN(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference),ac.dt_start))) AS agent_age_in_months,
  COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference) AS dt_metric_reference,
  YEAR(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference)) AS year,
  MONTH(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference)) AS month,
  DAY(COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference)) AS day
FROM
  demand_metrics dm
FULL OUTER JOIN
  quality_metrics qm
    ON dm.id_agent = qm.id_agent
    AND dm.dt_metric_reference = qm.dt_metric_reference
FULL OUTER JOIN
  ra_metrics rm
    ON rm.id_agent = COALESCE(dm.id_agent,qm.id_agent)
    AND rm.dt_metric_reference = COALESCE(dm.dt_metric_reference, qm.dt_metric_reference)
JOIN
  datalake_gsheets_clean.support_agents_department sad
    ON COALESCE(dm.id_agent, qm.id_agent,rm.id_agent) = sad.id_agent
    AND COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference) BETWEEN sad.dt_start AND COALESCE(sad.dt_end, NOW())
LEFT JOIN
  datalake_gsheets_clean.agents_control ac
    ON COALESCE(dm.id_agent, qm.id_agent, rm.id_agent) = ac.id_assignee
GROUP BY 
  COALESCE(dm.id_agent, qm.id_agent, rm.id_agent),
  sad.department,
  COALESCE(dm.dt_metric_reference, qm.dt_metric_reference, rm.dt_metric_reference)