SELECT DISTINCT
    r.id_reviewer AS sk_reviewer,
    r.id_user AS sk_user,
    r.reviewer_type,
    r.ts_created,
    YEAR(r.ts_created) AS year,
    MONTH(r.ts_created) AS month,
    DAY(r.ts_created) AS day
FROM
    datalake_inspections_clean.reviewer r
WHERE
    DATE(r.ts_created) = DATE('{year}-{month}-{day}')
