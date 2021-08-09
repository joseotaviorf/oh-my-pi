WITH agent AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.agent
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
    agent
WHERE
    row_n = 1
