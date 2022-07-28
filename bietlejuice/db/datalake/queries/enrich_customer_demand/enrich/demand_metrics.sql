WITH received_demand AS (
  SELECT
    id_agent,
    type,
    SUM(CAST(is_received_demand AS SMALLINT)) AS received_demand,
    DATE(ts_started) AS dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics_tasks
  GROUP BY 1,2,4
),
solved_demand AS (
  SELECT
    id_agent,
    type,
    SUM(CAST(is_solved_demand AS SMALLINT)) AS solved_demand,
    DATE(ts_completed) AS dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics_tasks
  GROUP BY 1,2,4
),
closed_demand AS (
  SELECT
    id_agent,
    type,
    SUM(CAST(is_closed_demand AS SMALLINT)) AS closed_demand,
    DATE(ts_closed) AS dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics_tasks
  GROUP BY 1,2,4
),
sla AS (
  SELECT
    id_agent,
    type,
    SUM(CAST(is_ticket_solved_in_time AS SMALLINT)) AS tickets_solved_in_time,
    SUM(CAST(is_ticket_not_solved_in_time AS SMALLINT)) AS tickets_not_solved_in_time,
    SUM(time_spent_solved_in_time) AS time_spent_on_tickets_solved_in_time,
    SUM(time_spent_not_solved_in_time) AS time_spent_on_tickets_not_solved_in_time,
    SUM(total_time_spent) AS total_time_spent,
    DATE(ts_completed) AS dt_metric_reference
  FROM
    datalake_customer_demand.demand_metrics_tasks
  WHERE
    ts_completed IS NOT NULL
  GROUP BY 1,2,8
)
SELECT
  id_agent,
  type,
  received_demand,
  solved_demand,
  closed_demand,
  tickets_solved_in_time,
  tickets_not_solved_in_time,
  time_spent_on_tickets_solved_in_time,
  time_spent_on_tickets_not_solved_in_time,
  total_time_spent,
  dt_metric_reference
FROM
  sla
FULL OUTER JOIN
  received_demand
    USING(id_agent, dt_metric_reference, type)
FULL OUTER JOIN
  solved_demand
    USING(id_agent, dt_metric_reference, type)
FULL OUTER JOIN
  closed_demand
    USING(id_agent, dt_metric_reference, type)
WHERE
  dt_metric_reference IS NOT NULL
  AND type IS NOT NULL
