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
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
