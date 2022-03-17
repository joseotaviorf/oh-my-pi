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
    DATE_TRUNC('week', ts_completed) as dt_final,
    ts_started,
    ts_completed
  FROM
    datalake_customer_demand.base_tasks
),
days_off AS (
  SELECT /*+ RANGE_JOIN(eb, 150) */
    id_task,
    dt_interval,
    COUNT(1) AS days_off
  FROM
    exploded_backlog eb
  JOIN
    weekends_and_holidays nw
      ON nw.dt_non_working BETWEEN DATE(eb.ts_started) AND eb.dt_interval
  GROUP BY 1,2
)
SELECT
  eb.id_agent,
  eb.type,
  DAYOFWEEK(eb.dt_interval) = 1 AS is_sunday,
  COUNT(1) AS daily_backlog,
  SUM(
    CASE 
      WHEN (TO_UNIX_TIMESTAMP(DATE_TRUNC('day',eb.dt_interval)) + 86399 - TO_UNIX_TIMESTAMP(ts_started))/(86400) - COALESCE(do.days_off, 0) < 0 THEN 1
      WHEN (TO_UNIX_TIMESTAMP(DATE_TRUNC('day',eb.dt_interval)) + 86399 - TO_UNIX_TIMESTAMP(ts_started))/(86400) - COALESCE(do.days_off, 0) <= sla_target THEN 1
      ELSE 0 
    END
  ) AS backlog_in_time,
  SUM(
    CASE 
      WHEN (TO_UNIX_TIMESTAMP(DATE_TRUNC('day',eb.dt_interval)) + 86399 - TO_UNIX_TIMESTAMP(ts_started))/(86400) - COALESCE(do.days_off, 0) > sla_target THEN 1
      ELSE 0
    END
  ) AS backlog_not_in_time,
  eb.dt_interval AS dt_metric_reference
FROM
  exploded_backlog eb
LEFT JOIN
  days_off do
    ON eb.id_task = do.id_task
    AND eb.dt_interval = do.dt_interval
WHERE
    eb.dt_interval IS NOT NULL 
    AND (
      dt_final IS NULL
      OR eb.dt_interval <> dt_final
    )
    AND eb.type IS NOT NULL
GROUP BY 1,2,3,7
