SELECT
    fi.sk_inspector,
    din.inspector_name,
    COUNT(fi.ts_inspected) AS total_inspected,
    COUNT(fi.ts_booking_created_local) AS total_booked,
    SUM(CAST((fi.is_not_canceled_by_inspector IS FALSE) AS SMALLINT)) AS total_cancelled_by_inspector,
    SUM(CAST(fi.is_not_canceled_by_inspector AS SMALLINT)) AS total_cancelled_by_others,
    COUNT(DISTINCT DATE(fi.ts_inspected)) AS total_days_worked,
    COUNT(DISTINCT DATE_TRUNC('WEEK', fi.ts_inspected)) AS total_weeks_worked,
    COUNT(fi.ts_inspected)*1.00/COUNT(DISTINCT DATE(fi.ts_inspected)) AS average_inspections,
    COUNT(fi.ts_inspected)*1.00/(COUNT(fi.ts_booking_created_local)-COUNT(fi.is_not_canceled_by_inspector)) AS inspections_conversion,
    ROUND(
        CASE
            WHEN DATEDIFF(din.dt_start, CURRENT_DATE) <= 15 THEN 2
            WHEN DATEDIFF(din.dt_start, CURRENT_DATE) <= 30 THEN 3
            WHEN COUNT(fi.ts_inspected)/COUNT(DISTINCT fi.ts_inspected) IS NULL THEN 1
            WHEN COUNT(fi.ts_inspected)/COUNT(DISTINCT fi.ts_inspected) IS NOT NULL
                AND COUNT(fi.ts_inspected)/(COUNT(fi.ts_booking_created_local)-COUNT(fi.is_not_canceled_by_inspector)) >= 0.9
                THEN (COUNT(fi.ts_inspected)/COUNT(DISTINCT DATE(fi.ts_inspected))) + 1
            WHEN COUNT(fi.ts_inspected)/COUNT(DISTINCT fi.ts_inspected) IS NOT NULL
                THEN (COUNT(fi.ts_inspected)/COUNT(DISTINCT DATE(fi.ts_inspected)))
        END, 0
    ) AS eligible_inspections,
    din.dt_start AS dt_inspector_started,
    DATE('{year}-{month}-{day}') AS dt_load,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    dw_inspections.fact_inspection AS fi
JOIN
    dw_inspections.dim_inspection AS di
        ON fi.sk_inspection = di.sk_inspection
LEFT JOIN
    dw_inspections.dim_inspector AS din
        ON fi.sk_inspector = din.sk_inspector
WHERE
    fi.ts_booking_inspected >= CURRENT_DATE + INTERVAL -60 DAY
    AND (
      di.status <> 'cancelled'
      OR fi.is_not_canceled_by_inspector IS NOT NULL
    )
GROUP BY 1, 2, 12