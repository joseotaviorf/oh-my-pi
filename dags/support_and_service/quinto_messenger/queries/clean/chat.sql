SELECT
    id,
    external_id AS id_external,
    source_id AS id_source,
    attributes,
    source,
    source_identity,
    status,
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
