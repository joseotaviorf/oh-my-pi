SELECT
	id AS id_appointment,
    external_appointment_id as id_external_appointment,
	external_appointment_id_mod as id_external_appointment_mod,
	inspection_id as id_inspection,
	inspection_id_mod as id_inspection_mod,
	inspector_id as id_inspector,
	inspector_id_mod as id_inspector_mod,
    rev,
	revtype AS rev_type,
	revend AS rev_end,
	status,
	status_mod,
	inspection_mod,
	observation,
	observation_mod,
    fixed_agent as is_fixed_agent,
	fixed_agent_mod as is_fixed_agent_mod,
    scheduled_date as dt_scheduled,
	scheduled_date_mod as dt_scheduled_mod,
    updated_at as ts_updated,
	updated_at_mod as ts_updated_mod,
    created_at as ts_created,
	created_at_mod as ts_created_mod,
    year,
    month,
    day
FROM
    datalake_inspections_raw.appointment_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}