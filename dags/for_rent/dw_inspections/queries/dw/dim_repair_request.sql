SELECT DISTINCT
    rr.id_repair_request,
    rr.type,
    rr.cost,
    rr.type AS repair_type,
    rr.comment,
    rr.responsibility,
    rr.repair_service,
    rr.item_name,
    rr.room_name,
    rr.ts_created,
    rr.ts_updated,
    NOW() AS ts_load,
    YEAR(rr.ts_updated) AS year,
    MONTH(rr.ts_updated) AS month,
    DAY(rr.ts_updated) AS day
FROM
    datalake_inspections.repair_request AS rr
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_updated DESC) = 1
