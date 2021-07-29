WITH reservations_events AS (
    SELECT
        GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
        GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
        GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
        event,
        GET_JSON_OBJECT(metadata,'$.created_at') as ts_event,
        GET_JSON_OBJECT(metadata, '$.event_data.Timestamp') AS ts_event_unix,
        year,
        month,
        day
    FROM
        datalake_bigfone_events.events
    WHERE
        provider = 'twilio'
        AND (
            GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
            OR GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Flex'
        )
        AND event LIKE 'reservation.%'
        AND GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') IS NOT NULL
        AND year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY 1,2,3,4,5,6,7,8,9
),
reservations_attributes AS (
    SELECT 
        GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
        GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
        GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
        COALESCE(
            GET_JSON_OBJECT(metadata,'$.event_data.WorkerSid'),
            GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.worker_sid')
        ) AS id_agent,
        GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueSid') AS id_queue,
        GET_JSON_OBJECT(metadata,'$.event_data.TaskQueueName') AS queue_name
    FROM
        datalake_bigfone_events.events
    WHERE
        provider = 'twilio'
        AND (
            GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
            OR GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Flex'
        )
        AND event = 'reservation.accepted'
        AND GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') IS NOT NULL
        AND year = {year}
        AND month = {month}
        AND day = {day}
),
tasks_events AS (
  SELECT
        GET_JSON_OBJECT(metadata,'$.event_data.TaskAttributes.call_sid') AS id_call,
        GET_JSON_OBJECT(metadata,'$.event_data.TaskSid') AS id_task,
        NULL AS id_reservation,
        event,
        GET_JSON_OBJECT(metadata,'$.created_at') as ts_event,
        GET_JSON_OBJECT(metadata, '$.event_data.Timestamp') AS ts_event_unix,
        year,
        month,
        day
  FROM
      datalake_bigfone_events.events
  WHERE
      provider = 'twilio'
      AND (
            GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Anyone'
            OR GET_JSON_OBJECT(metadata,'$.event_data.WorkflowName') = 'Assign to Flex'
      )
      AND (event = 'task.created' OR event='task.wrapup')
      AND year = {year}
      AND month = {month}
      AND day = {day}
  GROUP BY 1,2,3,4,5,6,7,8,9
),
call_flex_reservations AS (
    SELECT
        re1.id_call,
        re1.id_task,
        re1.id_reservation,
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
        MAX(year) AS year,
        MAX(month) AS month,
        MAX(day) AS day
    FROM
        reservations_events AS re1
    GROUP BY 1,2,3
),
full_events AS (
    SELECT 
        re.* 
    FROM 
        reservations_events re
    JOIN --filtering only answered reservations
        call_flex_reservations cr
            ON re.id_task = cr.id_task
            AND re.id_reservation = cr.id_reservation
            AND cr.is_answered
    UNION ALL
    SELECT * FROM tasks_events
),
-- The logic of the CTE below is highly dependent of the order of the events (now we are sorting using
-- the unix timestamp and untie by the alphabetical of the event).
-- Changing these event names may impact on the results of this CTE and consequently the whole call model
answered_time_calculations AS (
    SELECT
        fe.id_task,
        fe.id_reservation,
        CASE
            WHEN 
                event = 'reservation.created' 
                AND LEAD(event,1) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix, event DESC) = 'reservation.accepted' 
            THEN 
                LEAD(ts_event_unix,1) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix, event DESC) - COALESCE(LAG(ts_event_unix,1) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix, event DESC),ts_event_unix)
            WHEN 
                event = 'reservation.created' 
                AND LEAD(event,1) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix, event DESC) = 'reservation.completed' 
            THEN 
                LEAD(ts_event_unix,2) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix, event DESC) - ts_event_unix
        END AS seconds_queue_time,
        CASE
            WHEN event = 'reservation.accepted' THEN LEAD(ts_event_unix,1) OVER (PARTITION BY fe.id_task ORDER BY ts_event_unix) - ts_event_unix
        END AS seconds_talk_time
    FROM
        full_events fe
)
SELECT
    cr.id_call,
    cr.id_task,
    cr.id_reservation,
    reservations_attributes.id_agent,
    reservations_attributes.id_queue,
    reservations_attributes.queue_name,
    is_answered,
    is_timeout,
    is_rejected,
    SUM(seconds_queue_time) + SUM(seconds_talk_time) AS seconds_duration,
    SUM(seconds_queue_time) AS seconds_wait_time,
    SUM(seconds_talk_time) AS seconds_talk_time,
    CAST(FROM_UNIXTIME(ts_created_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(FROM_UNIXTIME(ts_created_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(FROM_UNIXTIME(ts_ended_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) AS ts_ended,
    FROM_UTC_TIMESTAMP(CAST(FROM_UNIXTIME(ts_ended_unix, 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP), 'Brazil/East') AS ts_ended_local,
    ts_created_unix,
    cr.year,
    cr.month,
    cr.day
FROM
    call_flex_reservations AS cr
LEFT JOIN
    answered_time_calculations AS atc
        ON cr.id_task = atc.id_task
        AND cr.id_reservation = atc.id_reservation
LEFT JOIN
    reservations_attributes
        ON cr.id_task = reservations_attributes.id_task
        AND cr.id_reservation = reservations_attributes.id_reservation
GROUP BY 1,2,3,4,5,6,7,8,9,13,14,15,16,17,18,19,20
