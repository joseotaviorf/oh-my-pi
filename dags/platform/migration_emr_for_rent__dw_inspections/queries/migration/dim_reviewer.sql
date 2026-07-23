SELECT
  sk_reviewer,
  sk_user,
  reviewer_type,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    r.id_reviewer AS sk_reviewer,
    r.id_user AS sk_user,
    r.reviewer_type,
    r.ts_created,
    r.ts_updated,
    NOW() AS ts_load,
    YEAR(TO_DATE(r.ts_updated)) AS year,
    MONTH(TO_DATE(r.ts_updated)) AS month,
    DAY(TO_DATE(r.ts_updated)) AS day,
    ROW_NUMBER() OVER (PARTITION BY id_reviewer ORDER BY ts_updated DESC) AS _w,
    id_reviewer
  FROM datalake_inspections.reviewer AS r
  WHERE
    CAST(r.ts_updated AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
