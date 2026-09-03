SELECT
    id,
    appointment_id AS id_appointment,
    calendar_id AS id_calendar,
    member_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.appointment_participant
