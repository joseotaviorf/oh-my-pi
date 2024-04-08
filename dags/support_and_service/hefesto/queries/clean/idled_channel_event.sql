SELECT
    id AS id_idled_channel_event,
    file_name,
    author,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.idled_channel_event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
