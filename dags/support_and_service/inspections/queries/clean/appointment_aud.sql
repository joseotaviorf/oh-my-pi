SELECT
	id AS id_appointment,
	external_appointment_id AS id_external_appointment,
	external_appointment_id_mod AS mod_id_external_appointment,
	inspection_id AS id_inspection,
	inspection_id_mod AS mod_id_inspection,
	inspector_id AS id_inspector,
	inspector_id_mod AS mod_id_inspector,
	rev,
	revtype AS rev_type,
	revend AS rev_end,
	status,
	mod_status,
	mod_inspection,
	observation,
	mod_observation,
	cancellation_reason,
	mod_cancellation_reason,
	fixed_agent AS is_fixed_agent,
	fixed_agent_mod AS mod_is_fixed_agent,
	scheduled_date AS dt_scheduled,
	scheduled_date_mod AS mod_dt_scheduled,
	updated_at AS ts_updated,
	updated_at_mod AS mod_ts_updated,
	created_at AS ts_created,
	created_at_mod AS mod_ts_created,
	year,
	month,
	day
FROM
	datalake_inspections_raw.appointment_aud
WHERE
	year = {year}
	AND month = {month}
	AND day = {day}