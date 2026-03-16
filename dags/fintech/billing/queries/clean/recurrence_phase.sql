SELECT
	id,
	recurrence_id AS id_recurrence,
	recurrence_phase_uuid AS uuid_ecurrence_phase,
	current_revision,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.recurrence_phase
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
