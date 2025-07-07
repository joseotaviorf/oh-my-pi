SELECT DISTINCT
    id_inspection AS sk_inspection,
    inspection_type,
    source,
    status,
    has_owner_accompanying,
    is_first_schedule,
    is_executed_in_first_schedule,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_inspections.inspection_booking
