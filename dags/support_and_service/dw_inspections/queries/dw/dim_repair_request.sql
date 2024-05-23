SELECT DISTINCT
    rr.id_repair_request,
    rr.type,
    rr.cost,
    rr.type AS repair_type,
    rr.comment,
    rr.repair_service,
    rr.ts_created,
    rr.ts_updated,
    NOW() AS ts_load,
    YEAR(rr.ts_updated) AS year,
    MONTH(rr.ts_updated) AS month,
    DAY(rr.ts_updated) AS day
FROM
    datalake_inspections_clean.repair_request AS rr
WHERE
    DATE(rr.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')