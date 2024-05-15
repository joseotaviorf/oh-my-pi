SELECT 
	id, 
    payload, 
	status, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM 
	datalake_checkout_raw.boleto_webhook