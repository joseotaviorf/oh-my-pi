WITH enrollment AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.enrollment
)
SELECT
    id,
    id_agent,
    id_program,
    details,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    enrollment
WHERE
    row_n = 1
