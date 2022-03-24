WITH weekends_and_holidays AS (
  SELECT
    ad.date AS dt_non_working
  FROM
    datalake_quintoandar.aux_date ad
  WHERE
    ad.weekend = 'Weekend'
  UNION
  SELECT
    sch.dt_holiday AS dt_non_working
  FROM
    datalake_gsheets_clean.service_city_holidays sch
  WHERE
    sch.category = 'Nacional'
),
task_days_until_solved AS (
  SELECT
    id_task,
    EXPLODE(
      SEQUENCE(
        DATE(ts_started),
        DATE(COALESCE(ts_completed, NOW()))
      )
    ) AS ts_interval
  FROM
    datalake_customer_demand.base_tasks
),
days_off AS (
  SELECT
    id_task,
    COUNT(1) AS days_off
  FROM
    task_days_until_solved tdus
  JOIN
    weekends_and_holidays nw
      ON DATE(tdus.ts_interval) = nw.dt_non_working
  GROUP BY 1
),
task_info AS (
  SELECT
    bt.id_task,
    bt.id_agent,
    bt.type,
    do.days_off,
    DATEDIFF(DATE(ts_completed), DATE(ts_started)) - COALESCE(do.days_off, 0) AS days_worked,
    bt.sla_target,
    bt.ts_completed,
    bt.ts_started
  FROM
    datalake_customer_demand.base_tasks bt
  LEFT JOIN
    days_off do
      ON bt.id_task = do.id_task
  WHERE
    bt.ts_completed IS NOT NULL
),
sla AS (
  SELECT
    ti.id_agent,
    ti.type,
    SUM(
      CASE 
        WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target THEN 1
        ELSE 0
      END
    ) AS tickets_solved_in_time,
    SUM(
      CASE 
        WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target THEN IF(ti.days_worked < 0, 0, ti.days_worked)
        ELSE 0
      END
    ) AS time_spent_on_tickets_solved_in_time,
    SUM(
      CASE 
        WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target THEN 0
        ELSE 1
      END
    ) AS tickets_not_solved_in_time,
    SUM(
      CASE 
        WHEN IF(ti.days_worked < 0, 0, ti.days_worked) > sla_target THEN IF(ti.days_worked < 0, 0, ti.days_worked)
        ELSE 0
      END
    ) AS time_spent_on_tickets_not_solved_in_time,
    SUM(IF(ti.days_worked < 0, 0, ti.days_worked)) AS total_time_spent,
    DATE(ti.ts_completed) AS dt_metric_reference
  FROM
    task_info ti
  GROUP BY 1,2,8
),
received_demand AS (
  SELECT
    id_agent,
    type,
    COUNT(1) AS received_demand,
    DATE(ts_started) AS dt_metric_reference
  FROM
    datalake_customer_demand.base_tasks
  GROUP BY 1,2,4
),
solved_demand AS (
  SELECT
    id_agent,
    type,
    COUNT(1) AS solved_demand,
    DATE(ts_completed) AS dt_metric_reference
  FROM
    datalake_customer_demand.base_tasks
  GROUP BY 1,2,4
)
SELECT
  id_agent,
  type,
  received_demand,
  solved_demand,
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
WHERE
  dt_metric_reference IS NOT NULL
  AND type IS NOT NULL