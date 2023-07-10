SELECT
    ib.id_inspector,
    ic.inspector_name,
    COUNT(ib.ts_inspected) AS total_inspected,
    COUNT(ib.ts_booking_created_local_tz) AS total_booked,
    SUM(CAST((ib.is_not_canceled_by_inspector IS FALSE) AS SMALLINT)) AS total_cancelled_by_inspector,
    SUM(CAST(ib.is_not_canceled_by_inspector AS SMALLINT)) AS total_cancelled_by_others,
    COUNT(DISTINCT DATE(ib.ts_inspected)) AS total_days_worked,
    COUNT(DISTINCT DATE_TRUNC('WEEK', ib.ts_inspected)) AS total_weeks_worked,
    COUNT(ib.ts_inspected)*1.00/COUNT(DISTINCT DATE(ib.ts_inspected)) AS average_inspections,
    COUNT(ib.ts_inspected)*1.00/(COUNT(ib.ts_booking_created_local_tz)-COUNT(ib.is_not_canceled_by_inspector)) AS inspections_conversion,
    ROUND(
        CASE
            WHEN DATEDIFF(DATE('{year}-{month}-{day}'), ic.dt_start) <= 15 THEN 2
            WHEN DATEDIFF(DATE('{year}-{month}-{day}'), ic.dt_start) <= 30 THEN 3
            WHEN COUNT(ib.ts_inspected)/COUNT(DISTINCT ib.ts_inspected) IS NULL THEN 1
            WHEN COUNT(ib.ts_inspected)/COUNT(DISTINCT ib.ts_inspected) IS NOT NULL
                AND COUNT(ib.ts_inspected)/(COUNT(ib.ts_booking_created_local_tz)-COUNT(ib.is_not_canceled_by_inspector)) >= 0.9
                THEN (COUNT(ib.ts_inspected)/COUNT(DISTINCT DATE(ib.ts_inspected))) + 1
            WHEN COUNT(ib.ts_inspected)/COUNT(DISTINCT ib.ts_inspected) IS NOT NULL
                THEN (COUNT(ib.ts_inspected)/COUNT(DISTINCT DATE(ib.ts_inspected)))
        END, 0
    ) AS eligible_inspections,
    ic.dt_start AS dt_inspector_started,
    DATE('{year}-{month}-{day}') AS dt_load,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_inspections.inspection_booking AS ib
LEFT JOIN
    datalake_gsheets_clean.inspectors_control AS ic
        ON ib.id_inspector = ic.id_inspector
WHERE
    ib.ts_booking_inspected_utc >= DATE('{year}-{month}-{day}') + INTERVAL -60 DAY
    AND (
      ib.status <> 'cancelled'
      OR ib.is_not_canceled_by_inspector IS NOT NULL
    )
    AND ib.id_inspector IS NOT NULL
GROUP BY 1, 2, 12