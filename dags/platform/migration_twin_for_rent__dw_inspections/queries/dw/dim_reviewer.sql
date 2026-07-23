SELECT DISTINCT
    r.id_reviewer AS sk_reviewer,
    r.id_user AS sk_user,
    r.reviewer_type,
    r.ts_created,
    r.ts_updated,
    NOW() AS ts_load,
    YEAR(r.ts_updated) AS year,
    MONTH(r.ts_updated) AS month,
    DAY(r.ts_updated) AS day
FROM
    datalake_inspections.reviewer r
WHERE
    DATE(r.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_reviewer ORDER BY ts_updated DESC) = 1
