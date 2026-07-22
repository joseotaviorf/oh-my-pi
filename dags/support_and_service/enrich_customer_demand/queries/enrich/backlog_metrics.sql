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
exploded_backlog AS (
  SELECT
    id_task,
    id_agent,
    type,
    sla_target,
    EXPLODE(
      SEQUENCE(
        DATE(ts_started),
        DATE(COALESCE(ts_completed, NOW()))
      )
    ) AS dt_interval,
    DATE(ts_completed) AS dt_final,
    ts_started,
    ts_completed
  FROM
    datalake_customer_demand.base_tasks
),
-- EMR-safe replacement for the Databricks-only RANGE_JOIN hint: the previous
-- BETWEEN range join degraded to a nested-loop/cartesian join on EMR Spark 3.5
-- (hint silently ignored), running on 1-2 tasks. Here we equi-join each exploded
-- day against the non-working calendar, then take a running count ordered by day.
-- Since exploded_backlog holds every day in [ts_started, dt_interval], the
-- cumulative SUM equals the count of non-working days in that range - identical
-- semantics, but fully parallelizable on both Databricks and EMR.
-- Partition and join include ts_started because base_tasks can emit the same
-- id_task twice (CRM UNION ALL Zendesk tickets) with different start dates.
marked_backlog AS (
  SELECT
    eb.id_task,
    eb.ts_started,
    eb.dt_interval,
    CASE
      WHEN nw.dt_non_working IS NOT NULL THEN 1
      ELSE 0
    END AS is_non_working
  FROM
    exploded_backlog AS eb
  LEFT JOIN
    weekends_and_holidays AS nw
      ON nw.dt_non_working = eb.dt_interval
),
days_off AS (
  SELECT
    id_task,
    ts_started,
    dt_interval,
    SUM(is_non_working) OVER (
      PARTITION BY id_task, ts_started
      ORDER BY dt_interval
    ) AS days_off
  FROM
    marked_backlog
)
SELECT
  eb.id_agent,
  eb.type,
  DAYOFWEEK(eb.dt_interval) = 1 AS is_sunday,
  COUNT(1) AS daily_backlog,
  SUM(
    CASE
      WHEN DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) - COALESCE(do.days_off, 0) <= sla_target THEN 1
      ELSE 0
    END
  ) AS backlog_in_time,
  SUM(
    CASE
      WHEN DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) - COALESCE(do.days_off, 0) > sla_target THEN 1
      ELSE 0
    END
  ) AS backlog_not_in_time,
  eb.dt_interval AS dt_metric_reference
FROM
  exploded_backlog AS eb
LEFT JOIN
  days_off AS do
    ON eb.id_task = do.id_task
    AND eb.ts_started = do.ts_started
    AND eb.dt_interval = do.dt_interval
WHERE
    eb.dt_interval IS NOT NULL
    AND (
      dt_final IS NULL
      OR eb.dt_interval <> dt_final
    )
    AND eb.type IS NOT NULL
GROUP BY 1,2,3,7
