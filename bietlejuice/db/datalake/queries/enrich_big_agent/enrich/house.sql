WITH house AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.house
)
SELECT
    id,
    details,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    house
WHERE
    row_n = 1
