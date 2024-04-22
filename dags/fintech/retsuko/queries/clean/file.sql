SELECT
    id,
    name,
    path,
    timestamp(created_at) AS ts_created,
    type
FROM
    datalake_retsuko_raw.file
