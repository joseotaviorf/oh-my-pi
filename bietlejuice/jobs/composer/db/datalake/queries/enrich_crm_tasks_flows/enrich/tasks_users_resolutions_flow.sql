WITH tasks AS (
    SELECT
        id AS id_task,
        MAX(id_contract) AS id_contract
    FROM
        datalake_crm.tasks
    GROUP BY 1
),
prev_tasks_full AS (
    SELECT DISTINCT
        tr.id_action AS id_action,
        COALESCE(DATE_FORMAT(tr.ts_action, 'YMMdd'), -1) AS id_action_date,
        COALESCE(tr.id_assignee, -1) AS id_assignee,
        COALESCE(DATE_FORMAT(tr.ts_completed, 'YMMdd'), -1) AS id_completed_date,
        t.id_contract,
        COALESCE(CAST(tr.id_origin AS BIGINT), -1) AS id_origin,
        COALESCE(CAST(tr.id_receiver AS BIGINT), -1) AS id_receiver,
        COALESCE(DATE_FORMAT(tr.ts_start, 'YMMdd'), -1) AS id_start_date,
        tr.id_task AS id_task,
        COALESCE(DATE_FORMAT(tr.ts_action, 'YMMdd'), -1) AS id_task_user_end_date,
        COALESCE(DATE_FORMAT(LAG(tr.ts_action) OVER(PARTITION BY tr.id_task ORDER BY tr.ts_action DESC), 'YMMdd'), -1) AS id_task_user_start_date,
        COALESCE(tr.id_user_action, -1) AS id_user_action,
        tr.id_workgroup,
        tr.action_type,
        tr.action_user_name,
        tr.action_type AS task_user_type,
        tr.origin,
        ROUND((TO_UNIX_TIMESTAMP(tr.ts_action, 'yyyy-MM-dd hh:mm:ss')
               - TO_UNIX_TIMESTAMP(LAG(tr.ts_action) OVER (PARTITION BY tr.id_task ORDER BY tr.ts_action), 'yyyy-MM-dd hh:mm:ss')) / 3600.0 , 2) AS task_user_resolve_hours,
        tr.type,
        DATE(tr.ts_action) AS dt_partition,
        tr.ts_action,
        tr.ts_start,
        tr.ts_action AS ts_task_user_end,
        LAG(tr.ts_action) OVER(PARTITION BY tr.id_task ORDER BY tr.ts_action) AS ts_task_user_start,
        tr.year,
        tr.month,
        tr.day
    FROM 
        datalake_crm_tasks_resolution.tasks_resolution tr
    JOIN
        tasks t
          USING(id_task)
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
    WHERE 
        action_type = 'REALIZE'
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
        t.ts_start,
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
    t.id_contract,
    t.id_origin AS id_origin,
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
    CAST(COALESCE(mrbu.task_user_resolve_hours, t.task_user_resolve_hours) AS FLOAT) AS task_user_resolve_hours,
    t.type, 
    t.action_type AS task_user_type,
    t.dt_partition,
    COALESCE(mrbu.ts_action, t.ts_action) AS ts_action,
    COALESCE(mrbu.ts_start, t.ts_start) AS ts_start,
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
WHERE 
    NOT(t.id_user_action = -1
          AND t.action_type = 'REALIZE')