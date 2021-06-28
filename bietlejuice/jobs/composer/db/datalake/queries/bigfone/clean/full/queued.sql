SELECT
    id,
    call_id AS id_call,
    queue,
    abandoned,
    joined_queue_time AS ts_joined_queue,
    left_queue_time AS ts_left_queue
FROM
    datalake_bigfone_raw.queued