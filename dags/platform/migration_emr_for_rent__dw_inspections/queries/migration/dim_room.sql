SELECT
  sk_room,
  room_name,
  room_type,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT
    r.id_room AS sk_room,
    r.room_name,
    r.room_type,
    r.ts_created,
    r.ts_updated,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day,
    ROW_NUMBER() OVER (PARTITION BY id_room ORDER BY ts_updated DESC) AS _w,
    id_room
  FROM datalake_inspections.room AS r
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
