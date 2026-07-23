SELECT
  sk_item_review,
  sk_item,
  review_comment,
  review_creator,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    ir.id_review AS sk_item_review,
    ir.id_item AS sk_item,
    ir.user_comment AS review_comment,
    ir.user_type AS review_creator,
    ir.ts_created,
    ir.ts_updated,
    NOW() AS ts_load,
    ir.year,
    ir.month,
    ir.day,
    ROW_NUMBER() OVER (PARTITION BY ir.id_review ORDER BY ir.ts_updated DESC) AS _w,
    ir.id_review
  FROM datalake_inspections.item_review AS ir
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
