SELECT 	
	id,
	house_external_id AS id_house,
	rev,
	revend AS rev_end,
	revtype AS rev_type,
	status_mod AS mod_status,
	status,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_rental_transact_raw.transact_flow_aud