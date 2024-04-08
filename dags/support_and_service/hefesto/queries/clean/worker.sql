SELECT
    id AS id_worker,
    sid AS id_worker_twilio,
    name,
    email,
    attributes,
    active,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(last_event_at) AS ts_last_event,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.worker
WHERE
    created_at >= '2024-03-01'
