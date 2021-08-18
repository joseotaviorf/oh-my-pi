SELECT
    id,
    cliente_id AS id_client,
    usuario_id AS id_user, 
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.cliente_arquivado