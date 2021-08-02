WITH user AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_kill_queue_clean.user
)
SELECT
    id,
    id_main,
    cell_phone,
    cpf,
    email,
    name,
    version,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    user
WHERE
    row_n = 1