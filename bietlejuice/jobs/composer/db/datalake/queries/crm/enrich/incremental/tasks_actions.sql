WITH exploded_actions AS (
  SELECT
    GET_JSON_OBJECT(REPLACE(id, '$', ''),"$.oid") AS id,
    EXPLODE(FROM_JSON(REPLACE(actions,'$',''), 
            'ARRAY<
                STRUCT<
                    _id: STRUCT<oid: STRING>,
                    type: STRING,
                    userName: STRING,
                    userId: INTEGER,
                    notificationSource: STRING,
                    metadata: STRUCT<key: STRING, oldValue: STRING>,
                    date: STRUCT<date: TIMESTAMP>
                >
            >'
        )) AS action
  FROM
      datalake_crm_clean.tasks
  WHERE
    -- Filtering out bugged tasks with more than 500 actions
    SIZE(FROM_JSON(actions,'ARRAY<STRUCT<>>')) <= 500
    AND year = '{year}'
    AND month = '{month}'
    AND day = '{day}'
)
SELECT
    action._id.oid AS id,
    id AS id_task,
    action.userId AS id_user_analyst,
    REPLACE(action.userName,'"') AS analyst_username,
    REPLACE(action.type,'"') AS action_type,
    action.metadata.key AS metadata_key,
    action.metadata.oldValue AS metadata_old_value,
    action.notificationSource AS notification_source,
    action.date.date AS ts_action,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    exploded_actions
WHERE
    DATE(action.date.date) = '{year}-{month}-{day}'
