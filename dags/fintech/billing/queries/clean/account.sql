SELECT
	id,
	actor_id AS id_actor,
	actor_role,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.account
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
