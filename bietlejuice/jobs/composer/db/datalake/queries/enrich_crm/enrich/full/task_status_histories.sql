WITH task_status_histories AS (
    SELECT
        GET_JSON_OBJECT(REPLACE(id, '$', ''), '$.oid') AS id,
        version,
        EXPLODE(
            FROM_JSON(
                REPLACE(history, '$', ''),
                'ARRAY<
                    STRUCT<
                        action: STRING,
                        status: STRING,
                        reason: STRING,
                        date: STRUCT<date: TIMESTAMP>,
                        _id: STRUCT<oid: STRING>,
                        actionUserId: INTEGER,
                        actionUserName: STRING,
                        assigneeId: INTEGER
                >>'
        )) AS history
    FROM
        datalake_crm_clean.task_status_histories
    WHERE
        -- Filtering out bugged tasks with more than 500 actions
        SIZE(FROM_JSON(history,'ARRAY<STRUCT<>>')) <= 500
)
SELECT DISTINCT
    history._id.oid AS id,
    id AS id_task,
    history.actionUserId AS id_user_action,
    history.assigneeId AS id_assignee,
    history.actionUserName AS action_user_name,
    history.action AS action_type,
    history.reason AS action_reason,
    history.status AS task_status,
    version,
    history.date.date AS ts_action,
    EXTRACT(YEAR FROM history.date.date) AS year,
    EXTRACT(MONTH FROM history.date.date) AS month,
    EXTRACT(DAY FROM history.date.date) AS day
FROM
    task_status_histories
