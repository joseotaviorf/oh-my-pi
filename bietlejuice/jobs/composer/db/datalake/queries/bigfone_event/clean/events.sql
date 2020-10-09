WITH events_filter AS (
    SELECT
        id,
        metadata,
        provider,
        event,
        event_timestamp,
        received_timestamp,
        year,
        month,
        day
    FROM datalake_bigfone_raw.event
    WHERE
        provider IN ('teravoz','twilio') 
        AND year = {year} 
        AND month = {month} 
        AND day = {day}
),
-- we need to do this filter because there is a Teravoz bug that generates service.command 
-- or/and recording.available events with wrong call id (Teravoz internal control call id).
lonely_events AS (
    SELECT 
        COUNT(GET_JSON_OBJECT(metadata, '$.call_id')) AS count_call_id, 
        GET_JSON_OBJECT(metadata, '$.call_id') AS call_id 
    FROM events_filter
    WHERE
        provider = 'teravoz' 
        AND (event = 'service.command' OR event = 'recording.available')
    GROUP BY 2
    -- Teravoz can generate 2 events with the same wrong call_id (recording and service) 
    HAVING count_call_id <= 2
)
SELECT 
    BIGINT(events.id) AS id,
    events.event AS event,
    GET_JSON_OBJECT(events.metadata, '$.call_id') AS id_call,
    events.metadata,
    events.provider,
    TO_TIMESTAMP(events.event_timestamp, 'yyyy-MM-dd HH:mm:ss') AS ts_created,
    TO_TIMESTAMP(FROM_UTC_TIMESTAMP(events.event_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') AS ts_created_local,
    TO_TIMESTAMP(events.received_timestamp, 'yyyy-MM-dd HH:mm:ss') AS ts_received,
    TO_TIMESTAMP(FROM_UTC_TIMESTAMP(events.received_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') AS ts_received_local,
    events.year AS year,
    events.month AS month,
    events.day AS day  
FROM events_filter events
LEFT JOIN lonely_events lonely
    ON lonely.call_id = GET_JSON_OBJECT(events.metadata, '$.call_id')
WHERE 
    lonely.call_id IS NULL
