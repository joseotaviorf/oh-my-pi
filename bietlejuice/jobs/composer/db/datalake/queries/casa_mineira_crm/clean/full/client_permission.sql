SELECT 
    id, 
    cliente_id AS id_client, 
    usuario_revogacao_id AS id_user_revogation, 
    usuario_id AS id_user, 
    criado_por AS created_by, 
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(revogado_em AS TIMESTAMP) AS ts_revoked 
FROM 
    datalake_casa_mineira_crm_raw.cliente_permissao 
