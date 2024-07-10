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
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
