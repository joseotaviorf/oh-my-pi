WITH issue_type AS (
  SELECT
    id_issue_type,
    issue_type,
    repair_suggestion
  FROM (
    SELECT
      it.id_issue_type,
      it.type AS issue_type,
      it.repair_suggestion,
      it.ts_updated,
      FIRST(it.ts_updated) OVER (PARTITION BY it.id_issue_type ORDER BY it.ts_updated DESC) AS _w
    FROM datalake_inspection_services_clean.issue_type AS it
  ) AS _t
  WHERE
    ts_updated = _w
)
SELECT
  id_item_issue,
  id_issue_type,
  id_item,
  id_room,
  id_assessment,
  id_inspection,
  uuid,
  issue_type,
  display_type,
  item_group_name,
  item_group_type,
  room_name,
  item_comment,
  issue_comment,
  repair_suggestion,
  is_active,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT
    ii.id_item_issue,
    it.id_issue_type,
    ii.id_item,
    i.id_room,
    i.id_assessment,
    i.id_inspection,
    ii.uuid,
    it.issue_type,
    i.display_type,
    i.item_group_name,
    i.item_group_type,
    i.room_name,
    i.comment AS item_comment,
    CASE WHEN ii.comment = '' THEN NULL ELSE ii.comment END AS issue_comment,
    it.repair_suggestion,
    ii.is_active,
    ii.ts_created,
    ii.ts_updated,
    ii.year,
    ii.month,
    ii.day,
    ROW_NUMBER() OVER (PARTITION BY ii.id_item_issue ORDER BY ii.ts_updated DESC) AS _w
  FROM datalake_inspection_services_clean.item_issue AS ii
  JOIN issue_type AS it
    ON ii.id_type = it.id_issue_type
  LEFT JOIN datalake_inspections.item AS i
    ON i.id_item = ii.id_item
  WHERE
    MAKE_DATE(ii.year, ii.month, ii.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
