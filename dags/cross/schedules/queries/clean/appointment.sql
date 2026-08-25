SELECT
    id,
    main_appointment_id AS id_main_appointment,
    location_reference_id AS id_location_reference,
    internal_reference_id AS id_internal_reference,
    version,
    type,
    dated_at,
    slot_of_day,
    duration_in_slots,
    slot_mask,
    status,
    last_app_origin,
    code,
    business_context,
    confirmed AS is_confirmed,
    fixed_agent AS is_fixed_agent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.appointment
