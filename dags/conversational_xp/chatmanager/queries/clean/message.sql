SELECT
    id,
    incremental_id AS id_incremental,
    destination,
    headers,
    payload,
    published,
    message_partition,
    TIMESTAMP_MILLIS(creation_time) AS ts_created
FROM
    datalake_chatmanager_raw.message
