 SELECT DISTINCT
    rr.id_repair_request,
    rr.type,
    rr.cost,
    rr.type AS repair_type,
    rr.comment,
    rr.repair_service,
    rr.ts_created,
    NOW() AS ts_load,
    YEAR(r.ts_created) AS year,
    MONTH(r.ts_created) AS month,
    DAY(r.ts_created) AS day
FROM
    datalake_inspections_clean.repair_request AS rr
WHERE
    DATE(r.ts_created) = DATE('{year}-{month}-{day}')