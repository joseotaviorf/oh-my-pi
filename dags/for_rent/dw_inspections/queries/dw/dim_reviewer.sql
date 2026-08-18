WITH ranked_reviewer AS (
    SELECT
        r.id_reviewer AS sk_reviewer,
        r.id_user AS sk_user,
        r.reviewer_type,
        r.ts_created,
        r.ts_updated,
        ROW_NUMBER() OVER (PARTITION BY r.id_reviewer ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_inspections.reviewer AS r
    WHERE
        DATE(r.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    sk_reviewer,
    sk_user,
    reviewer_type,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    ranked_reviewer
WHERE
    rn = 1
