SELECT
    id,
    incremental_id AS id_incremental,
    destination,
    headers,
    payload,
    published,
    message_partition,
    creation_time AS ts_creation_time
FROM
    datalake_rental_guarantee_raw.message
    