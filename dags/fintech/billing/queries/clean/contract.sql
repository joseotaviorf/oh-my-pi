SELECT
	id,
	recurrence_uuid AS uuid_recurrence,
	status,
	current_revision,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_billing_raw.contract
