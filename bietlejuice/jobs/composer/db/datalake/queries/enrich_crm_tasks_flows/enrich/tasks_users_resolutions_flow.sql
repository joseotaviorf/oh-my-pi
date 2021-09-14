WITH max_date AS (
    SELECT
        ct.id_task,
        MAX(DATE(ct.ts_action)) AS dt_max
    FROM 
        datalake_crm_tasks_resolution.tasks_resolution ct
    WHERE
        year = '{year}'
        AND month = '{month}'
        AND day = '{day}'
    GROUP BY 1
),
prev_tasks AS (
    SELECT DISTINCT
        COALESCE(DATE_FORMAT(ct.ts_action, 'YMMdd'), -1) AS id_action_date,
        COALESCE(CAST(CAST(ct.id_assignee AS DECIMAL) AS BIGINT), -1) AS id_assignee,
        COALESCE(DATE_FORMAT(ct.ts_completed, 'YMMdd'), -1) AS id_completed_date, 
        COALESCE(CAST(CAST(ct.id_origin AS DECIMAL) AS BIGINT), -1) AS id_origin,
        COALESCE(CAST(ct.id_receiver AS BIGINT), -1) AS id_receiver,
        COALESCE(DATE_FORMAT(ct.ts_start, 'YMMdd'), -1) AS id_start_date,
        ct.id_task AS id_task,
        COALESCE(DATE_FORMAT(ct.ts_action, 'YMMdd'), -1) AS id_task_user_end_date,
        COALESCE(DATE_FORMAT(LAG(ts_action) OVER(PARTITION BY ct.id_task ORDER BY ts_action DESC), 'YMMdd'), -1) AS id_task_user_start_date,
        COALESCE(CAST(CAST(ct.id_user_action AS DECIMAL) AS BIGINT), -1) AS id_user_action,
        ct.action_type,
        ct.action_user_name,
        ct.action_type AS task_user_type,
        ROUND((TO_UNIX_TIMESTAMP(ct.ts_action, 'yyyy-MM-dd hh:mm:ss')
               - TO_UNIX_TIMESTAMP(LAG(ct.ts_action) OVER (PARTITION BY ct.id_task ORDER BY ct.ts_action), 'yyyy-MM-dd hh:mm:ss')) / 3600.0 , 1) AS task_user_resolve_hours,
        DATE(ct.ts_action) AS dt_partition,
        ct.ts_action,
        ct.ts_action AS ts_task_user_end,
        LAG(ts_action) OVER(PARTITION BY ct.id_task ORDER BY ts_action DESC) AS ts_task_user_start,
        year,
        month,
        day
    FROM 
        datalake_crm_tasks_resolution.tasks_resolution ct
    JOIN 
        max_date md
            ON ct.id_task = md.id_task
            AND DATE(ct.ts_action) = md.dt_max
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
    COALESCE(mrbu.id_action_date, t.id_action_date) AS id_action_date,
    t.id_assignee,
    t.id_completed_date,
    t.id_origin,
    t.id_receiver,
    t.id_start_date,
    t.id_task,
    COALESCE(mrbu.id_task_user_end_date, t.id_task_user_end_date) AS id_task_user_end_date,
    COALESCE(mrbu.id_task_user_start_date, t.id_task_user_start_date) AS id_task_user_start_date,
    t.id_user_action,
    t.action_type,
    t.action_user_name,
    COALESCE(mrbu.task_user_resolve_hours, t.task_user_resolve_hours) AS task_user_resolve_hours,
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