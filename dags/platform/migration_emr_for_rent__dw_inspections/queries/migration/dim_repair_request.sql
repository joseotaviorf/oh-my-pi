SELECT
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
  ts_load,
  year,
  month,
  day
FROM (
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
    YEAR(TO_DATE(rr.ts_updated)) AS year,
    MONTH(TO_DATE(rr.ts_updated)) AS month,
    DAY(TO_DATE(rr.ts_updated)) AS day,
    ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_updated DESC) AS _w
  FROM datalake_inspections.repair_request AS rr
) AS _t
WHERE
  _w = 1
