SELECT
  sk_reviewer,
  sk_assessment,
  sk_inspection,
  approval_reason,
  approval_comment,
  approval_type,
  is_approved,
  ts_approved,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    r.id_reviewer AS sk_reviewer,
    r.id_assessment AS sk_assessment,
    CAST(r.id_inspection AS STRING) AS sk_inspection,
    r.approval_reason,
    r.approval_comment,
    r.approval_type,
    r.is_approved,
    COALESCE(r.ts_approved, r.ts_updated) AS ts_approved,
    NOW() AS ts_load,
    r.year,
    r.month,
    r.day,
    ROW_NUMBER() OVER (PARTITION BY id_reviewer ORDER BY COALESCE(COALESCE(r.ts_approved, r.ts_updated), r.ts_updated) DESC) AS _w,
    id_reviewer,
    r.ts_updated
  FROM datalake_inspections.reviewer AS r
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
