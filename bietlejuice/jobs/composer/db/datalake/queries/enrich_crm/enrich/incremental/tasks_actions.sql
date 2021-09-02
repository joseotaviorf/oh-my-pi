WITH exploded_actions AS (
  SELECT
    GET_JSON_OBJECT(REPLACE(id, '$', ''),"$.oid") AS id,
    EXPLODE(
        FROM_JSON(
            REPLACE(actions,'$',''), 
            'ARRAY<
                STRUCT<
                    _id: STRUCT<oid: STRING>,
                    type: STRING,
                    userName: STRING,
                    userId: INTEGER,
                    notificationSource: STRING,
                    metadata: STRING,
                    date: STRUCT<date: TIMESTAMP>
                >
            >'
    )) AS action,
    year,
    month,
    day
  FROM
      datalake_crm_clean.tasks
  WHERE
    -- Filtering out bugged tasks with more than 500 actions
    SIZE(FROM_JSON(actions,'ARRAY<STRUCT<>>')) <= 500
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
exploded_analyst_started AS (
    SELECT
        GET_JSON_OBJECT(REPLACE(id, '$', ''),"$.oid") AS id, 
        EXPLODE(
            FROM_JSON(
                REPLACE(analyst_started, '$', ''),
                'ARRAY<
                        STRUCT<
                            _id: STRUCT<oid: STRING>,
                            date: STRUCT<date: TIMESTAMP>,
                            userId: INTEGER,
                            userName: STRING
                        >
                    >'
        )) AS analyst_started,
        year,
        month,
        day
    FROM
        datalake_crm_clean.tasks
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
)
SELECT
    ea.action._id.oid AS id,
    ea.id AS id_task,
    es.analyst_started._id.oid AS id_analyst_started,
    ea.action.userId AS id_user_action,
    es.analyst_started.userId AS id_user_analyst_started,
    REPLACE(ea.action.userName,'"') AS action_user_name,
    es.analyst_started.userName AS analyst_started_user_name,
    REPLACE(ea.action.type,'"') AS action_type,
    GET_JSON_OBJECT(ea.action.metadata, '$.key') AS metadata_key,
    GET_JSON_OBJECT(ea.action.metadata, '$.oldValue') AS metadata_old_value,
    ea.action.notificationSource AS notification_source,
    ea.action.date.date AS ts_action,
    es.analyst_started.date.date AS ts_analyst_started,
    ea.year,
    ea.month,
    ea.day
FROM
    exploded_actions AS ea
LEFT JOIN
    exploded_analyst_started AS es
        ON ea.id = es.id
WHERE
    DATE(ea.action.date.date) = DATE('{year}-{month}-{day}')
