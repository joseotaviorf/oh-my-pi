SELECT
	id,
	actor_id AS id_actor,
	actor_role,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.account
