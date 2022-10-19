WITH reservations AS (
    SELECT
        id_reservation,
        queue_name,
        ts_created,
        ts_ended,
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
),
twilio_timestamp AS (
    SELECT
        id_reservation,
        ts_created_local AS ts_twilio_created_local,
        ts_created_utc AS ts_twilio_created_utc
    FROM
        datalake_bigfone_twilio.call_flex_events
    WHERE
        event_type = 'reservation.accepted'
)
SELECT
    r.id_reservation AS sk_task,
    queue_name,
    dt_updated,
    ts_created,
    ts_ended,
    tt.ts_twilio_created_local,
    tt.ts_twilio_created_utc,
    NOW() AS ts_load
FROM
    reservations r
INNER JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = r.dt_updated
LEFT JOIN
    twilio_timestamp tt
        ON tt.id_reservation = r.id_reservation
