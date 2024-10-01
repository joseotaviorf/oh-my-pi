SELECT
    MD5(CAST(COALESCE(COALESCE(id_appointment, id_main_appointment), -1) AS STRING)) AS sk_appointment,
    COALESCE(id_appointment, -1) AS sk_is_appointment,
    COALESCE(id_main_appointment, -1) AS sk_main_appointment,
    COALESCE(id_inspection, -1) AS sk_inspection,
    COALESCE(id_inspector, -1) AS sk_inspector,
    MD5(
      COALESCE(type, 'N/A') ||
      COALESCE(status, 'N/A')  ||
      COALESCE(status_made_by, 'N/A') ||
      COALESCE(status_description, 'N/A') ||
      COALESCE(cancellation_reason, 'N/A') ||
      COALESCE(source, 'N/A')
    ) AS sk_appointment_component,
    slot_of_day,
    duration_in_slots,
    is_fixed_agent,
    is_confirmed,
    is_first_schedule,
    is_d0_canceled,
    is_d1_canceled,
    is_not_canceled_by_inspector,
    ts_appointment_inspected_utc,
    ts_appointment_inspected_local_tz,
    ts_appointment_created_utc,
    ts_appointment_updated_utc,
    ts_appointment_created_local_tz,
    ts_appointment_updated_local_tz,
    ts_first_appointment_cancelled_utc,
    ts_first_appointment_cancelled_local_tz,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_inspections.appointment_inspection
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
