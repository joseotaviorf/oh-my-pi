WITH count_agency AS (
    SELECT
        id_house,
        COUNT(1) AS total_houses
    FROM
        datalake_big_agent_clean.agency
    WHERE 
        ts_deleted IS NULL
    GROUP BY 1
),

agency AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER(PARTITION BY a.id_house ORDER BY a.ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.agency AS a
    LEFT JOIN 
        count_agency AS ca
            ON a.id_house=ca.id_house
    WHERE 
        ts_deleted IS NULL 
        OR ca.id_house IS NULL
)

SELECT
    id,
    id_house,
    id_enrollment,
    dt_since,
    ts_created,
    ts_deleted,
    ts_updated,
    year,
    month,
    day
FROM
    agency
WHERE
    row_n = 1
