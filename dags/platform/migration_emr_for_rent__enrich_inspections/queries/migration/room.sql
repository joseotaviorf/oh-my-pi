WITH room_type AS (
  SELECT
    id_room_type,
    room_type
  FROM (
    SELECT
      rt.id_room_type,
      rt.type AS room_type,
      rt.ts_updated,
      FIRST(rt.ts_updated) OVER (PARTITION BY rt.id_room_type ORDER BY rt.ts_updated DESC) AS _w
    FROM datalake_inspection_services_clean.room_type AS rt
  ) AS _t
  WHERE
    ts_updated = _w
)
SELECT
  r.id_room,
  r.id_assessment,
  rt.id_room_type,
  r.room_name,
  rt.room_type,
  r.ts_created,
  r.ts_updated,
  r.year,
  r.month,
  r.day
FROM datalake_inspection_services_clean.room AS r
JOIN room_type AS rt
  ON r.id_type = rt.id_room_type
WHERE
  MAKE_DATE(r.year, r.month, r.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
