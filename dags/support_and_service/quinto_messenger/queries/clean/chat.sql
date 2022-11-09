SELECT id,
    external_id,
    source,
    source_id,
    source_identity,
    status,
    attributes,
    created_at as ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.chat
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
