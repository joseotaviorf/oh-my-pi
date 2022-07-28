WITH program AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.program
)
SELECT
    id,
    name,
    code,
    details,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    program
WHERE
    row_n = 1
