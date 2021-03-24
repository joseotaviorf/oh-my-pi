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
        )) AS history,
        year,
        month,
        day
    FROM
        datalake_crm_clean.task_status_histories
    WHERE
        year = '{year}'
        AND month = '{month}'
        AND day = '{day}'
)
SELECT
    history._id.oid AS id_action,
    history.actionUserId AS id_user_action,
    history.assigneeId AS id_assignee,
    history.actionUserName AS action_user_name,
    history.action AS action_type,
    history.reason AS action_reason,
    history.status AS task_status,
    version,
    history.date.date AS ts_action,
    year,
    month,
    day   
FROM
    task_status_histories
WHERE 
    DATE(history.date.date) = DATE('{year}-{month}-{day}')
