SELECT
    i.id_inspection AS sk_inspection,
    i.inspection_type,
    i.source,
    i.status,
    i.has_owner_accompanying,
    i.is_first_schedule,
    i.is_executed_in_first_schedule,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load
FROM
    datalake_inspections.inspection_booking i