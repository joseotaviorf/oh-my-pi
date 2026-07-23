WITH item_type AS (
  SELECT
    id_item_type,
    item_type,
    media_type,
    display_type
  FROM (
    SELECT
      id_item_type,
      it.type AS item_type,
      it.media_type,
      it.display_type,
      it.ts_updated,
      FIRST(it.ts_updated) OVER (PARTITION BY it.id_item_type ORDER BY it.ts_updated DESC) AS _w
    FROM datalake_inspection_services_clean.item_type AS it
  ) AS _t
  WHERE
    it.ts_updated = _w
)
SELECT
  id_item,
  id_previous_item,
  id_item_type,
  id_item_group,
  id_external_item,
  id_room,
  id_assessment,
  id_inspection,
  id_inspector,
  uuid,
  item_type,
  media_type,
  display_type,
  room_name,
  item_group_name,
  item_group_type,
  comment,
  is_present,
  count,
  is_active,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    i.id_item,
    i.id_previous_item,
    it.id_item_type,
    i.id_item_group,
    i.id_main AS id_external_item,
    r.id_room,
    r.id_assessment,
    ih.id_inspection,
    ih.id_inspector,
    i.uuid,
    it.item_type,
    it.media_type,
    it.display_type,
    r.room_name,
    ig.item_group_name,
    ig.item_group_type,
    CASE WHEN i.comment = '' THEN NULL ELSE i.comment END AS comment,
    i.is_present,
    i.count,
    i.is_active,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day,
    ROW_NUMBER() OVER (PARTITION BY i.id_item ORDER BY i.ts_updated DESC) AS _w
  FROM datalake_inspection_services_clean.item AS i
  LEFT JOIN item_type AS it
    ON i.id_type = it.id_item_type
  LEFT JOIN datalake_inspections.item_group AS ig
    ON i.id_item_group = ig.id_item_group
  LEFT JOIN datalake_inspection_services_clean.room AS r
    ON ig.id_room = r.id_room
  LEFT JOIN datalake_inspection_services_clean.assessment AS a
    ON r.id_assessment = a.id_assessment
  LEFT JOIN datalake_inspection_services_clean.inspection AS ih
    ON a.id_inspection = ih.id_inspection
  WHERE
    MAKE_DATE(i.year, i.month, i.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
