SELECT
  sk_repair_request,
  sk_exemption_granted_by,
  exemption_granted_by,
  responsibility,
  is_exempted,
  is_improper_repair,
  ts_granted,
  ts_load,
  year,
  month,
  day
FROM (
  SELECT DISTINCT
    re.id_repair_request AS sk_repair_request,
    re.id_granted_by AS sk_exemption_granted_by,
    re.exemption_granted_by,
    re.responsibility,
    re.is_exempted,
    re.is_improper_repair,
    re.ts_granted,
    NOW() AS ts_load,
    re.year,
    re.month,
    re.day,
    ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_granted DESC) AS _w,
    id_repair_request
  FROM datalake_inspections.repair_exempted AS re
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
