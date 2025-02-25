SELECT
    id AS id_appointment,
	external_appointment_id AS id_external_appointment,
    schedules_appointment_id AS id_schedules,
    inspection_id AS id_inspection,
    inspector_id AS id_inspector,
    status,
    observation,
    cancellation_reason,
	fixed_agent AS is_fixed_agent,
	scheduled_date AS dt_scheduled,
    created_at AS ts_created,
    updated_at AS ts_updated,
	year,
	month,
	day
FROM
	datalake_inspection_services_raw.appointment
