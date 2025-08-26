SELECT 
    id,
    uuid,
    lead_id AS id_lead,
    consorciado_id AS id_consorciado,
    checkout_url,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_consorcio_raw."order" 