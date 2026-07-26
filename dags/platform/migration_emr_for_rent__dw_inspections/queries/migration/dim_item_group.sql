WITH item_group_comments AS (
  SELECT
    i.id_item_group,
    SUM(
      CAST(CASE
        WHEN NOT ii.id_item_issue IS NULL AND i.display_type IN ('CHECK_DESCRIPTION', 'CHECK')
        THEN TRUE
        ELSE FALSE
      END AS INT)
    ) > 0 AS has_item_checklist,
    SUM(
      CAST(CASE
        WHEN NOT ii.id_item_issue IS NULL
        AND i.display_type IN ('CHIP_CHOICE_SINGLE', 'OVERVIEW_WITH_CONDITIONS')
        THEN TRUE
        ELSE FALSE
      END AS INT)
    ) > 0 AS has_item_chip_choice,
    SUM(
      CAST(CASE
        WHEN NOT i.comment IS NULL AND i.item_type IN ('overview', 'other')
        THEN TRUE
        WHEN NOT ii.issue_comment IS NULL
        THEN TRUE
        ELSE FALSE
      END AS INT)
    ) > 0 AS has_inspector_open_comment
  FROM datalake_inspections.item AS i
  LEFT JOIN datalake_inspections.item_issue AS ii
    ON ii.id_item = i.id_item
  WHERE
    i.year = {year} AND i.month = {month} AND i.day = {day}
  GROUP BY
    1
)
SELECT
  sk_item_group,
  item_group_name,
  item_group_type,
  status,
  has_item_checklist,
  has_item_chip_choice,
  has_inspector_open_comment,
  is_inferior_quality,
  is_active_status,
  is_active_inferior_quality,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    ig.id_item_group AS sk_item_group,
    ig.item_group_name,
    ig.item_group_type,
    ig.status,
    COALESCE(igc.has_item_checklist, FALSE) AS has_item_checklist,
    COALESCE(igc.has_item_chip_choice, FALSE) AS has_item_chip_choice,
    COALESCE(igc.has_inspector_open_comment, FALSE) AS has_inspector_open_comment,
    ig.is_inferior_quality,
    ig.is_active_status,
    ig.is_active_inferior_quality,
    ig.ts_created,
    ig.ts_updated,
    NOW() AS ts_load,
    ig.year,
    ig.month,
    ig.day,
    ROW_NUMBER() OVER (PARTITION BY ig.id_item_group ORDER BY ig.ts_updated DESC) AS _w,
    ig.id_item_group
  FROM datalake_inspections.item_group AS ig
  LEFT JOIN item_group_comments AS igc
    ON igc.id_item_group = ig.id_item_group
  WHERE
    MAKE_DATE(ig.year, ig.month, ig.day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
