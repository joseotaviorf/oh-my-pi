WITH task_status_histories AS (
    SELECT
        GET_JSON_OBJECT(REPLACE(id, '$', ''), '$.oid') AS id,
        version,
        EXPLODE(
            FROM_JSON(
                REPLACE(history, '$', ''),
                'ARRAY<STRING>'
        )) AS history
    FROM
        datalake_crm_clean.task_status_histories
    WHERE
        -- Filtering out bugged tasks with more than 500 actions
        SIZE(FROM_JSON(history,'ARRAY<STRUCT<>>')) <= 500
)
SELECT DISTINCT
    GET_JSON_OBJECT(history, '$._id.oid') AS id,
    id AS id_task,
    GET_JSON_OBJECT(history, '$.actionUserId') AS id_user_action,
    GET_JSON_OBJECT(history, '$.assigneeId') AS id_assignee,
    GET_JSON_OBJECT(history, '$.actionUserName') AS action_user_name,
    GET_JSON_OBJECT(history, '$.action') AS action_type,
    GET_JSON_OBJECT(history, '$.reason') AS action_reason,
    GET_JSON_OBJECT(history, '$.status') AS task_status,
    version,
    GET_JSON_OBJECT(history, '$.date.date') AS ts_action,
    EXTRACT(YEAR FROM GET_JSON_OBJECT(history, '$.date.date')) AS year,
    EXTRACT(MONTH FROM GET_JSON_OBJECT(history, '$.date.date')) AS month,
    EXTRACT(DAY FROM GET_JSON_OBJECT(history, '$.date.date')) AS day
FROM
    task_status_histories
