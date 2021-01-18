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
)
SELECT
    r.id_reservation AS sk_task,
    queue_name,
    ts_created,
    ts_ended,
    dt_updated,
    NOW() AS ts_load
FROM
    reservations r
INNER JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = r.dt_updated
