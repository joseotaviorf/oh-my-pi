WITH weekends_and_holidays AS (
  SELECT
    ad.date AS dt_non_working
  FROM
    datalake_quintoandar.aux_date AS ad
  WHERE
    ad.weekend = 'Weekend'
  UNION
  SELECT
    sch.dt_holiday AS dt_non_working
  FROM
    datalake_gsheets_clean.service_city_holidays AS sch
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
    task_days_until_solved AS tdus
  INNER JOIN
    weekends_and_holidays AS nw
      ON DATE(tdus.ts_interval) = nw.dt_non_working
  GROUP BY 1
),
task_info AS (
  SELECT
    bt.id_task,
    bt.id_agent,
    bt.id_user,
    bt.id_taxonomy,
    bt.id_tags,
    bt.id_main_department,
    bt.type,
    bt.origin,
    bt.status,
    bt.sla_target,
    bt.agent_email,
    do.days_off,
    DATEDIFF(DATE(ts_completed), DATE(ts_started)) - COALESCE(do.days_off, 0) AS days_worked,
    bt.ts_completed,
    bt.ts_started,
    bt.ts_zendesk_started,
    bt.ts_budget,
    bt.ts_closed
  FROM
    datalake_customer_demand.base_tasks AS bt
  LEFT JOIN
    days_off AS do
      ON bt.id_task = do.id_task
)
SELECT
  ti.id_task,
  ti.id_agent,
  ti.id_user,
  ti.id_taxonomy,
  ti.id_tags,
  ti.id_main_department,
  ti.type,
  ti.sla_target,
  ti.agent_email,
  ti.origin,
  ti.status,
  CASE
    WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target THEN IF(ti.days_worked < 0, 0, ti.days_worked)
    ELSE 0
  END AS time_spent_solved_in_time,
  CASE
    WHEN IF(ti.days_worked < 0, 0, ti.days_worked) > sla_target THEN IF(ti.days_worked < 0, 0, ti.days_worked)
    ELSE 0
  END AS time_spent_not_solved_in_time,
  IF(ti.days_worked < 0, 0, ti.days_worked) AS days_worked,
  IF(ti.days_off < 0, 0, ti.days_off) AS days_off,
  IF(ti.days_worked < 0, 0, ti.days_worked) AS total_time_spent,
  CASE
    WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target THEN TRUE
    ELSE FALSE
  END AS is_ticket_solved_in_time,
  CASE
    WHEN IF(ti.days_worked < 0, 0, ti.days_worked) <= sla_target
      OR ISNULL(ti.days_worked) THEN FALSE
    ELSE TRUE
  END AS is_ticket_not_solved_in_time,
  CASE
    WHEN ts_started IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_received_demand,
  CASE
    WHEN ts_completed IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_solved_demand,
  CASE
    WHEN ts_closed IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_closed_demand,
  ti.ts_started,
  ti.ts_completed,
  ti.ts_zendesk_started,
  ti.ts_budget,
  ti.ts_closed
FROM
  task_info AS ti
WHERE
  ti.type IS NOT NULL
