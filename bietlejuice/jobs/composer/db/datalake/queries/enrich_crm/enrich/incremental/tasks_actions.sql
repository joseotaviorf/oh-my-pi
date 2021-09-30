WITH exploded_actions AS (
  SELECT
    GET_JSON_OBJECT(REPLACE(id, '$', ''),"$.oid") AS id,
    EXPLODE(FROM_JSON(REPLACE(actions,'$',''), 'ARRAY<STRING>')) AS action,
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
)
SELECT
    GET_JSON_OBJECT(action, '$._id.oid') AS id,
    id AS id_task,
    CAST(GET_JSON_OBJECT(action, '$.userId') AS INT) AS id_user_action,
    REPLACE(GET_JSON_OBJECT(action, '$.userName'),'"') AS action_user_name,
    REPLACE(GET_JSON_OBJECT(action, '$.type'),'"') AS action_type,
    GET_JSON_OBJECT(action, '$.metadata.key') AS metadata_key,
    GET_JSON_OBJECT(action, '$.metadata.oldValue') AS metadata_old_value,
    GET_JSON_OBJECT(action, '$.notificationSource') AS notification_source,
    CAST(GET_JSON_OBJECT(action, '$.date.date') AS TIMESTAMP) AS ts_action,
    year,
    month,
    day
FROM
    exploded_actions
WHERE
    DATE(GET_JSON_OBJECT(action, '$.date.date')) = DATE('{year}-{month}-{day}')
