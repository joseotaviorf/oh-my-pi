with exploded_events AS (
  SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    GET_JSON_OBJECT(REPLACE(taskid, '$', ''), '$.oid') AS id_task,
    EXPLODE_OUTER(FROM_JSON(inboundevents, 'array<string>')) AS events_json,
    CAST(GET_JSON_OBJECT(REPLACE(createdat, '$',  ''), '$.date') AS TIMESTAMP) AS ts_created,
    CAST(GET_JSON_OBJECT(REPLACE(updatedat, '$',  ''), '$.date') AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
  FROM
    datalake_autodialer_raw.taskreferenceinboundeventhistories
)
SELECT
  id,
  id_task,
  GET_JSON_OBJECT(events_json, '$.taskReferenceEventOrigin') AS task_reference_event_origin,
  GET_JSON_OBJECT(events_json, '$.dialStatus') AS dial_status,
  CAST(DATE_FORMAT(GET_JSON_OBJECT(REPLACE(events_json, '$', ''), '$.eventDate.date'), 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) AS event_date,
  CAST(DATE_FORMAT(GET_JSON_OBJECT(REPLACE(events_json, '$', ''), '$.snoozed.date'), 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) AS snoozed,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM
  exploded_events
WHERE
    year={year} 
    AND month={month} 
    AND day={day}