SELECT DISTINCT
  r.id_reservation,
  hl.id_house_listing,
  r.id_house,
  r.status,
  r.cancellation_reason,
  r.installments AS total_installments,
  CAST(r.value/r.installments AS DECIMAL(19,2)) AS monthly_value,
  CAST(r.value AS DECIMAL(19,2)) AS total_value,
  is_ongoing,
  DATE_FORMAT(dd.month_start,'yyyyMM') AS accrual_month,
  IF(r.installments <= 1, DATE(r.ts_created), ADD_MONTHS(DATE(r.ts_created), (r.installments - 1))) AS dt_end_payment,
  DATE(r.ts_created) AS dt_created
FROM
  datalake_kill_queue.reservation AS r
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON r.id_house = hl.id_house
    AND r.ts_created >= COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') 
    AND r.ts_created < COALESCE(hl.ts_listing_version_end, NOW())
INNER JOIN 
  dw_public.dim_date AS dd
    ON dd.month_start BETWEEN DATE_TRUNC('month', DATE(r.ts_created))
      AND DATE_TRUNC('month', IF(r.installments <= 1, DATE(r.ts_created), ADD_MONTHS(DATE(r.ts_created), (r.installments - 1))))