WITH earnings AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.earnings
)

SELECT
    id,
    id_agency,
    id_agent,
    id_program,
    id_house_external,
    status,
    type,
    failure_count,
    details,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    earnings
WHERE
    row_n = 1