WITH reservations AS (
    SELECT
        id_reservation,
        id_task,
        id_call,
        id_agent,
        id_queue,
        is_answered,
        is_timeout,
        is_rejected,
        seconds_duration,
        seconds_wait_time,
        seconds_talk_time,
        DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
    FROM
        datalake_bigfone_twilio.call_flex_reservations
),
last_updated_reservations AS (
    SELECT
        id_reservation,
        MAX(dt_updated) AS dt_last_updated
    FROM
        reservations
    GROUP BY 1
)
SELECT
    r.id_reservation AS sk_task,
    COALESCE(id_call,id_task) AS sk_call,
    id_agent AS sk_agent,
    id_queue AS sk_queue,
    is_answered,
    is_timeout,
    is_rejected,
    seconds_duration,
    seconds_wait_time,
    seconds_talk_time
FROM
    reservations r
INNER JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = r.dt_updated
