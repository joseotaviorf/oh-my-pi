WITH reservations_events AS (
    SELECT
        id_call,
        id_task,
        id_reservation,
        id_agent,
        CASE
            WHEN event_type = 'reservation.created' THEN id_task_queue
        END AS id_queue,
        CASE
            WHEN event_type = 'reservation.created' THEN task_queue_name
        END AS queue_name,
        event_type AS event,
        GET_JSON_OBJECT(metadata, '$.event_data.Timestamp') AS ts_event_unix,
        year,
        month,
        day
    FROM
        datalake_bigfone.call_flex_events
    WHERE
        event_type LIKE 'reservation.%'
        AND id_reservation IS NOT NULL
        AND year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
call_flex_reservations AS (
    SELECT
        re1.id_task,
        re1.id_reservation,
        re1.id_agent,
        re2.id_queue,
        re2.queue_name,
        COUNT(
            CASE
                WHEN re1.event = 'reservation.accepted' THEN re1.id_reservation
            END
        ) > 0 AS is_answered,
        COUNT(
            CASE
                WHEN re1.event = 'reservation.timeout' THEN re1.id_reservation
            END
        ) > 0 AS is_timeout,
        COUNT(
            CASE
                WHEN re1.event = 'reservation.rejected' THEN re1.id_reservation
            END
        ) > 0 AS is_rejected,
        MIN(re1.ts_event_unix) AS ts_created_unix,
        MAX(re1.ts_event_unix) AS ts_ended_unix,
        re1.year,
        re1.month,
        re1.day
    FROM
        reservations_events AS re1
    LEFT JOIN
        reservations_events AS re2
            ON re1.id_task = re2.id_task
            AND re1.id_reservation = re2.id_reservation
            AND re2.queue_name IS NOT NULL
    GROUP BY 1,2,3,4,5,11,12,13
),
answered_time_calculations AS (
    SELECT
        re.id_task,
        re.id_reservation,
        CASE
            WHEN event = 'reservation.created' AND LEAD(event,1) OVER (PARTITION BY cr.id_task ORDER BY ts_event_unix) = 'reservation.accepted' THEN LEAD(ts_event_unix,1) OVER (PARTITION BY re.id_task ORDER BY ts_event_unix) - COALESCE(LAG(ts_event_unix,1) OVER (PARTITION BY re.id_task ORDER BY ts_event_unix),ts_event_unix)
            WHEN event = 'reservation.created' AND LEAD(event,1) OVER (PARTITION BY re.id_task ORDER BY ts_event_unix) = 'reservation.completed' THEN LEAD(ts_event_unix,2) OVER (PARTITION BY re.id_task ORDER BY ts_event_unix) - ts_event_unix
        END AS seconds_queue_time,
        CASE
            WHEN event = 'reservation.accepted' THEN LEAD(ts_event_unix,1) OVER (PARTITION BY re.id_task ORDER BY ts_event_unix) - ts_event_unix
        END AS seconds_talk_time
    FROM
        reservations_events re
    JOIN
        call_flex_reservations cr
            ON re.id_task = cr.id_task
            AND re.id_reservation = cr.id_reservation
            AND cr.is_answered
)
SELECT
    cr.id_task,
    cr.id_reservation,
    cr.id_agent,
    cr.id_queue,
    cr.queue_name,
    is_answered,
    is_timeout,
    is_rejected,
    ts_ended_unix - ts_created_unix AS seconds_duration,
    SUM(seconds_queue_time) AS seconds_wait_time,
    SUM(seconds_talk_time) AS seconds_talk_time,
    CAST(FROM_UNIXTIME(ts_created_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) ts_created,
    CAST(FROM_UNIXTIME(ts_ended_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) ts_ended,
    year,
    month,
    day
FROM
    call_flex_reservations AS cr
LEFT JOIN
    answered_time_calculations AS atc
        ON cr.id_task = atc.id_task
        AND cr.id_reservation = atc.id_reservation
GROUP BY 1,2,3,4,5,6,7,8,9,12,13,14,15,16
