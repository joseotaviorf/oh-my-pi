WITH lonely_events AS (
  SELECT
    COUNT(GET_JSON_OBJECT(metadata, call_id)) AS count_call_id,
    GET_JSON_OBJECT(metadata, call_id) AS call_id
  FROM datalake_bigfone_clean.event
  WHERE
    provider = 'teravoz'
    AND (
      event_type = 'service.command' OR event_type = 'recording.available'
    )
    AND CAST(ts_created AS DATE) = CAST('{year}-{month}-{day}' AS DATE)
  GROUP BY
    2
  HAVING
    count_call_id <= 2
)
SELECT
  BIGINT(events.id) AS id,
  events.event_type AS event,
  GET_JSON_OBJECT(events.metadata, call_id) AS id_call,
  events.metadata,
  events.provider,
  TO_TIMESTAMP(events.ts_created, 'yyyy-MM-dd HH:mm:ss') AS ts_created,
  TO_TIMESTAMP(
    FROM_UTC_TIMESTAMP(CAST(events.ts_created AS TIMESTAMP), 'Brazil/East'),
    'yyyy-MM-dd HH:mm:ss'
  ) AS ts_created_local,
  TO_TIMESTAMP(events.ts_received, 'yyyy-MM-dd HH:mm:ss') AS ts_received,
  TO_TIMESTAMP(
    FROM_UTC_TIMESTAMP(CAST(events.ts_received AS TIMESTAMP), 'Brazil/East'),
    'yyyy-MM-dd HH:mm:ss'
  ) AS ts_received_local,
  events.year AS year,
  events.month AS month,
  events.day AS day
FROM datalake_bigfone_clean.event AS events
LEFT JOIN lonely_events AS lonely
  ON lonely.call_id = GET_JSON_OBJECT(events.metadata, call_id)
WHERE
  lonely.call_id IS NULL
  AND provider IN ('teravoz', 'twilio')
  AND CAST(ts_created AS DATE) = CAST('{year}-{month}-{day}' AS DATE)
