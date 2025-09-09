SELECT
	id,
	contract_id AS id_contract,
	idempotency_id AS id_idempotency,
	revision,
	contract_data,
	created_at AS ts_created,
	processed_at AS ts_processed
FROM 
	datalake_billing_raw.contract_revision
