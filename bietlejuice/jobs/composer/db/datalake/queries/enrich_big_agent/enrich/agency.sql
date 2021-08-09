WITH agency AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.agency
)
SELECT
    id,
    id_house,
    id_enrollment,
    details,
    dt_since,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    agency
WHERE
    row_n = 1
