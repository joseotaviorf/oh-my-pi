SELECT
    id,
    incremental_id AS id_incremental,
    destination,
    headers,
    payload,
    published,
    message_partition,
    creation_time,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.message