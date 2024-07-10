SELECT
    id AS id_worker_channel,
    sid AS id_worker_channel_twilio,
    worker_id AS id_worker,
    task_channel_sid AS id_task_channel_twilio,
    worker_sid AS id_worker_twilio,
    name,
    capacity,
    available AS is_available,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(last_event_at) AS ts_last_event,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.worker_channel
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
