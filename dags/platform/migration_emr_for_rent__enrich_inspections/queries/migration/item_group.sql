WITH item_group_type AS (
  SELECT
    id_item_group_type,
    item_group_type
  FROM (
    SELECT
      igt.id_item_group_type,
      igt.type AS item_group_type,
      igt.ts_updated,
      FIRST(igt.ts_updated) OVER (PARTITION BY igt.id_item_group_type ORDER BY igt.ts_updated DESC) AS _w
    FROM datalake_inspection_services_clean.item_group_type AS igt
  ) AS _t
  WHERE
    igt.ts_updated = _w
)
SELECT
  id_item_group,
  id_item_group_type,
  id_room,
  id_main,
  item_group_name,
  item_group_type,
  status,
  is_inferior_quality,
  is_active_status,
  is_active_inferior_quality,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT
    ig.id_item_group,
    igt.id_item_group_type,
    ig.id_room,
    ig.id_main,
    ig.name AS item_group_name,
    igt.item_group_type,
    ig.status,
    ig.is_inferior_quality,
    ig.is_active_status,
    ig.is_active_inferior_quality,
    ig.ts_created,
    ig.ts_updated,
    ig.year,
    ig.month,
    ig.day,
    ROW_NUMBER() OVER (PARTITION BY ig.id_item_group ORDER BY ig.ts_updated DESC) AS _w
  FROM datalake_inspection_services_clean.item_group AS ig
  JOIN item_group_type AS igt
    ON ig.id_type = igt.id_item_group_type
  WHERE
    MAKE_DATE(ig.year, ig.month, ig.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
