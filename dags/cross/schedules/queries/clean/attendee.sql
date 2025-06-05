SELECT
    id,
    appointment_id AS id_appointment,
    internal_reference_id AS id_internal_reference,
    version,
    prefers_contact,
    intention,
    internal_reference_name,
    attendee_type,
    attendee_date_time,
    confirmed AS is_confirmed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.attendee
