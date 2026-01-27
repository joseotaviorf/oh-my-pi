SELECT 
	id,
	incremental_id AS id_incremental,
	destination,
	headers,
	payload,
	creation_datetime AS ts_created
FROM 
	datalake_rental_transact_raw.message
