WITH teravoz AS (
    SELECT
        CONCAT(c.id, ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY c.destination_called_number, c.seconds_talk_duration, c.ts_started)) AS id_event,
        c.id AS id_call,
        c.call_direction AS direction,
        c.seconds_talk_duration,
        "historical_teravoz" AS provider,
        CASE
            WHEN c.status = "no answer" THEN  "actor.noanswer"
            WHEN c.status = "abandon" THEN "call.queue-abandon"
            ELSE CONCAT("call.", c.status)
        END AS event, 
        TO_TIMESTAMP(c.ts_started_local, 'yyyy-MM-dd HH:mm:ss') AS ts_created,
        TO_TIMESTAMP(FROM_UTC_TIMESTAMP(c.ts_started_local, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') AS ts_created_local,
        NULL AS ts_received,
        NULL AS ts_received_local,
        c.year,
        c.month,
        c.day
    FROM
        datalake_teravoz_clean.calls c
    LEFT JOIN
        datalake_bigfone_clean.event e
            ON c.id = e.call_id
    WHERE
        e.call_id IS NULL
        AND c.year = {year}
        AND c.month = {month}
        AND c.day = {day}
),
bigfone AS (
    SELECT 
        e.id AS id_event,
        COALESCE(e.call_id, GET_JSON_OBJECT(e.metadata,'$.call_id')) AS id_call,
        GET_JSON_OBJECT(e.metadata,'$.direction') AS direction,
        NULL AS seconds_talk_duration,
        e.provider,
        e.event,
        TO_TIMESTAMP(e.event_timestamp, 'yyyy-MM-dd HH:mm:ss') AS ts_created,
        TO_TIMESTAMP(FROM_UTC_TIMESTAMP(e.event_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') AS ts_created_local,
        TO_TIMESTAMP(e.received_timestamp, 'yyyy-MM-dd HH:mm:ss') AS ts_received,
        TO_TIMESTAMP(FROM_UTC_TIMESTAMP(e.received_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') AS ts_received_local,
        e.year,
        e.month,
        e.day
    FROM
        datalake_bigfone_clean.event e
    WHERE
        e.provider = "teravoz"
        AND e.year = {year}
        AND e.month = {month}
        AND e.day = {day}
)
SELECT
    *
FROM
    teravoz
UNION ALL
SELECT 
    *
FROM
    bigfone