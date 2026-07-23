SELECT
  sk_item,
  item_type,
  item_media_type,
  item_comment,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT
    i.id_item AS sk_item,
    i.item_type,
    i.media_type AS item_media_type,
    i.comment AS item_comment,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load,
    i.year,
    i.month,
    i.day,
    ROW_NUMBER() OVER (PARTITION BY id_item ORDER BY ts_updated DESC) AS _w,
    id_item
  FROM datalake_inspections.item AS i
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
