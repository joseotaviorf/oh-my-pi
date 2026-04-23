SELECT
	id,
	recurrence_uuid AS uuid_recurrence,
	business_entity_id,
	source,
	business_context,
	current_revision,
	idempotency_key,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.recurrence
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
