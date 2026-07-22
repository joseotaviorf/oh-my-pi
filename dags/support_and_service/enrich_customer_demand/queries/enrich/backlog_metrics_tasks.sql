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
),
days_off AS (
    SELECT
        id_task,
        COUNT(1) AS days_off,
        dt_interval
    FROM
        exploded_backlog AS eb
    INNER JOIN
        weekends_and_holidays AS nw
            ON nw.dt_non_working BETWEEN DATE(eb.ts_started) AND eb.dt_interval
    GROUP BY 1,3
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
  DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) - COALESCE(do.days_off, 0) AS days_worked,
  DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) AS days_worked_with_days_offs,
  COALESCE(do.days_off, 0) AS days_off,
  TRUE AS is_daily_backlog,
  CASE
    WHEN DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) - COALESCE(do.days_off, 0) <= sla_target THEN TRUE
    ELSE FALSE
  END AS is_backlog_in_time,
  CASE
    WHEN DATEDIFF(DATE(eb.dt_interval), DATE(ts_started)) - COALESCE(do.days_off, 0) > sla_target THEN TRUE
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
  days_off AS do
    ON eb.id_task = do.id_task
    AND eb.dt_interval = do.dt_interval
WHERE
    eb.dt_interval = DATE('{year}-{month}-{day}')
    AND eb.type IS NOT NULL
