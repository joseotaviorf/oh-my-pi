SELECT 	
	id,
	house_external_id AS id_house,
	status,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_rental_transact_raw.transact_flow