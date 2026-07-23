SELECT
  sk_item,
  sk_previous_item,
  sk_external_item,
  sk_item_group,
  sk_room,
  sk_assessment,
  sk_inspection,
  has_inspector_comment,
  is_present,
  is_active,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT
    i.id_item AS sk_item,
    i.id_previous_item AS sk_previous_item,
    i.id_external_item AS sk_external_item,
    i.id_item_group AS sk_item_group,
    i.id_room AS sk_room,
    i.id_assessment AS sk_assessment,
    CAST(i.id_inspection AS STRING) AS sk_inspection,
    NOT i.comment IS NULL AS has_inspector_comment,
    i.is_present,
    i.is_active,
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
