SELECT
    id AS id_queue_event,
    queue_id AS id_queue,
    queue_friendly_name,
    queue_attributes,
    event_type,
    author,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.queue_event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
