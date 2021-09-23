WITH prev_tasks_full AS (
    SELECT DISTINCT
        ct.id_action AS id_action,
        COALESCE(DATE_FORMAT(ct.ts_action, 'YMMdd'), -1) AS id_action_date,
        COALESCE(ct.id_assignee, -1) AS id_assignee,
        COALESCE(DATE_FORMAT(ct.ts_completed, 'YMMdd'), -1) AS id_completed_date, 
        COALESCE(ct.id_origin, -1) AS id_origin,
        COALESCE(CAST(ct.id_receiver AS BIGINT), -1) AS id_receiver,
        COALESCE(DATE_FORMAT(ct.ts_start, 'YMMdd'), -1) AS id_start_date,
        ct.id_task AS id_task,
        COALESCE(DATE_FORMAT(ct.ts_action, 'YMMdd'), -1) AS id_task_user_end_date,
        COALESCE(DATE_FORMAT(LAG(ts_action) OVER(PARTITION BY ct.id_task ORDER BY ts_action DESC), 'YMMdd'), -1) AS id_task_user_start_date,
        COALESCE(ct.id_user_action, -1) AS id_user_action,
        ct.id_workgroup,
        ct.action_type,
        ct.action_user_name,
        ct.action_type AS task_user_type,
        ct.origin,
        ROUND((TO_UNIX_TIMESTAMP(ct.ts_action, 'yyyy-MM-dd hh:mm:ss')
               - TO_UNIX_TIMESTAMP(LAG(ct.ts_action) OVER (PARTITION BY ct.id_task ORDER BY ct.ts_action), 'yyyy-MM-dd hh:mm:ss')) / 3600.0 , 1) AS task_user_resolve_hours,
        ct.type,
        DATE(ct.ts_action) AS dt_partition,
        ct.ts_action,
        ct.ts_action AS ts_task_user_end,
        LAG(ts_action) OVER(PARTITION BY ct.id_task ORDER BY ts_action) AS ts_task_user_start,
        year,
        month,
        day
    FROM 
        datalake_crm_tasks_resolution.tasks_resolution ct
),
prev_tasks AS (
    SELECT *
    FROM
        prev_tasks_full
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
prev_max_realized_by_user AS (
    SELECT
        id_task,
        id_user_action,
        MAX(ts_action) AS ts_max_action
    FROM 
        prev_tasks
    WHERE action_type = 'REALIZE'
        AND id_user_action != -1
    GROUP BY 1, 2
),
max_realized_by_user AS (
    SELECT
        t.id_action_date,
        t.id_task,
        t.id_task_user_end_date,
        t.id_task_user_start_date,
        t.id_user_action,
        t.action_type,
        t.task_user_resolve_hours,
        t.ts_action,
        t.ts_task_user_start,
        t.ts_task_user_end
    FROM 
        prev_tasks t
    JOIN 
        prev_max_realized_by_user prev_max
            ON t.id_task = prev_max.id_task
            AND t.id_user_action = prev_max.id_user_action
            AND t.ts_action = prev_max.ts_max_action
            AND t.action_type = 'REALIZE'
)
SELECT DISTINCT
    CAST(t.id_action AS STRING) AS id_action,
    CAST(COALESCE(mrbu.id_action_date, t.id_action_date) AS BIGINT) AS id_action_date,
    CAST(t.id_assignee AS BIGINT) AS id_assignee,
    CAST(t.id_completed_date AS BIGINT) AS id_completed_date,
    CAST(t.id_origin AS STRING) AS id_origin,
    CAST(t.id_receiver AS BIGINT) AS id_receiver,
    CAST(t.id_start_date AS BIGINT) AS id_start_date,
    CAST(t.id_task AS STRING) AS id_task,
    CAST(COALESCE(mrbu.id_task_user_end_date, t.id_task_user_end_date) AS BIGINT) AS id_task_user_end_date,
    CAST(COALESCE(mrbu.id_task_user_start_date, t.id_task_user_start_date) AS BIGINT) AS id_task_user_start_date,
    CAST(t.id_user_action AS BIGINT) AS id_user_action,
    CAST(t.id_workgroup AS STRING) AS id_workgroup,
    t.action_type,
    t.action_user_name,
    t.origin,
    COALESCE(mrbu.task_user_resolve_hours, t.task_user_resolve_hours) AS task_user_resolve_hours,
    t.type, 
    t.action_type AS task_user_type,
    t.dt_partition,
    COALESCE(mrbu.ts_action, t.ts_action) AS ts_action,
    COALESCE(mrbu.ts_task_user_start, t.ts_task_user_start) AS ts_task_user_start,
    COALESCE(mrbu.ts_task_user_end, t.ts_task_user_end) AS ts_task_user_end,
    year,
    month,
    day
FROM 
    prev_tasks t
LEFT JOIN 
    max_realized_by_user mrbu
        ON t.id_task = mrbu.id_task
            AND t.id_user_action = mrbu.id_user_action
            AND t.action_type = mrbu.action_type
WHERE NOT(t.id_user_action = -1
          AND t.action_type = 'REALIZE')