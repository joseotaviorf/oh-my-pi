SELECT
    id,
    reservation_id AS id_reservation,
    version, 
    created_at AS ts_created,
    updated_at AS ts_updated,
    year, 
    month, 
    day
FROM
    datalake_kill_queue_raw.charge
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}