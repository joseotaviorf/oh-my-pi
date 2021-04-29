SELECT
    id,
    metadata,
    provider,
    event_timestamp,
    received_timestamp,
    call_id,
    type AS event,
    year,
    month,
    day
FROM
    datalake_bigfone_raw.event
WHERE
    event_timestamp >= DATE('{year}-{month}-{day}')
    AND event_timestamp < DATE_ADD(DATE('{year}-{month}-{day}'),1)
