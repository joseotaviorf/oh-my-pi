WITH documentation AS (
    SELECT 
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_kill_queue_clean.documentation
)
SELECT
    id,
    id_house,
    id_tenant,
    version,
    is_active,
    ts_expired,
    ts_event,
    ts_created,
    ts_updated,
    year,
    month, 
    day
FROM
    documentation
WHERE
    row_n = 1