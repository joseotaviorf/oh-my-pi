SELECT
    id,
    appointment_id AS id_appointment,
    updated_by_reference_id AS id_updated_by_reference,
    updated_by_reference_name,
    version,
    status,
    category_name,
    category_description,
    reason_name,
    reason_description,
    visitor_can_see AS is_visitor_can_see,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.appointment_history
