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
    year = {year}
    AND month = {month}
    AND day = {day}
