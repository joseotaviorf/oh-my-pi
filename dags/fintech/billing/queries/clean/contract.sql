SELECT
	id,
	recurrence_uuid AS uuid_recurrence,
	status,
	current_revision,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.contract
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
