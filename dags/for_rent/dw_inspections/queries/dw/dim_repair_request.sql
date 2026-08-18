WITH ranked_repair_request AS (
    SELECT
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
        ROW_NUMBER() OVER (PARTITION BY rr.id_repair_request ORDER BY rr.ts_updated DESC) AS rn
    FROM
        datalake_inspections.repair_request AS rr
)
SELECT DISTINCT
    id_repair_request,
    type,
    cost,
    repair_type,
    comment,
    responsibility,
    repair_service,
    item_name,
    room_name,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    ranked_repair_request
WHERE
    rn = 1
