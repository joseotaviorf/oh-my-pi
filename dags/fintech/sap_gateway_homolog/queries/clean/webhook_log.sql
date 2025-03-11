SELECT 
    id AS id_webhook_log, 
    webhook_status, 
    status, 
    status_reason, 
    errors, 
    job_identifier,
    entity_type,
    idoc, 
    payload, 
    created_at AS ts_created, 
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_sap_gateway_homolog_raw.webhook_log