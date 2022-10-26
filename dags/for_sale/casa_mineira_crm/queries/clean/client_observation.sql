SELECT 
    id, 
    cliente_id AS id_client, 
    criado_por AS created_by, 
    CAST(criado_em AS TIMESTAMP) AS ts_created 
FROM 
    datalake_casa_mineira_crm_raw.cliente_observacao