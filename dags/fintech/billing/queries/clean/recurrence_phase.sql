SELECT
	id,
	recurrence_id AS id_recurrence,
	recurrence_phase_uuid AS uuid_ecurrence_phase,
	current_revision,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_billing_raw.recurrence_phase
