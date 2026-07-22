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
-- EMR-safe replacement for the BETWEEN range join: a pure range predicate
-- degrades to a nested-loop/cartesian join on EMR Spark 3.5. Build a tiny
-- cumulative calendar spine, then equi-join start and end dates so days_off
-- is cal_end.cum - cal_start.cum + cal_start.is_non_working. Preserves the
-- daily incremental filter pushdown (unlike a per-task running window).
calendar AS (
  SELECT
    ad.date AS dt_calendar,
    CASE
      WHEN nw.dt_non_working IS NOT NULL THEN 1
      ELSE 0
    END AS is_non_working,
    SUM(
      CASE
        WHEN nw.dt_non_working IS NOT NULL THEN 1
        ELSE 0
      END
    ) OVER (
      ORDER BY ad.date
    ) AS cum_days_off
  FROM
    datalake_quintoandar.aux_date AS ad
  LEFT JOIN
    weekends_and_holidays AS nw
      ON nw.dt_non_working = ad.date
),
exploded_backlog AS (
  SELECT
    id_task,
    id_agent,
    id_user,
    id_taxonomy,
    id_tags,
    id_main_department,
    type,
    sla_target,
    agent_email,
    origin,
    status,
    EXPLODE(
      SEQUENCE(
        DATE(ts_started),
        DATE(COALESCE(ts_completed, NOW()))
      )
    ) AS dt_interval,
    DATE(ts_completed) AS dt_final,
    ts_started,
    ts_zendesk_started,
    ts_budget,
    ts_completed
  FROM
    datalake_customer_demand.base_tasks
)
SELECT
  eb.id_task,
  eb.id_agent,
  eb.id_user,
  eb.id_taxonomy,
  eb.id_tags,
  eb.id_main_department,
  eb.type,
  eb.sla_target,
  eb.agent_email,
  eb.origin,
  eb.status,
  DATEDIFF(DATE(eb.dt_interval), DATE(eb.ts_started))
    - COALESCE(cal_end.cum_days_off - cal_start.cum_days_off + cal_start.is_non_working, 0) AS days_worked,
  DATEDIFF(DATE(eb.dt_interval), DATE(eb.ts_started)) AS days_worked_with_days_offs,
  COALESCE(cal_end.cum_days_off - cal_start.cum_days_off + cal_start.is_non_working, 0) AS days_off,
  TRUE AS is_daily_backlog,
  CASE
    WHEN DATEDIFF(DATE(eb.dt_interval), DATE(eb.ts_started))
      - COALESCE(cal_end.cum_days_off - cal_start.cum_days_off + cal_start.is_non_working, 0) <= sla_target THEN TRUE
    ELSE FALSE
  END AS is_backlog_in_time,
  CASE
    WHEN DATEDIFF(DATE(eb.dt_interval), DATE(eb.ts_started))
      - COALESCE(cal_end.cum_days_off - cal_start.cum_days_off + cal_start.is_non_working, 0) > sla_target THEN TRUE
    ELSE FALSE
  END AS is_backlog_not_in_time,
  eb.ts_started,
  eb.ts_completed,
  eb.ts_zendesk_started,
  eb.ts_budget,
  eb.dt_interval AS dt_metric_reference,
  YEAR(eb.dt_interval) AS year,
  MONTH(eb.dt_interval) AS month,
  DAY(eb.dt_interval) AS day
FROM
  exploded_backlog AS eb
LEFT JOIN
  calendar AS cal_start
    ON cal_start.dt_calendar = DATE(eb.ts_started)
LEFT JOIN
  calendar AS cal_end
    ON cal_end.dt_calendar = eb.dt_interval
WHERE
  eb.dt_interval = DATE('{year}-{month}-{day}')
  AND eb.type IS NOT NULL
