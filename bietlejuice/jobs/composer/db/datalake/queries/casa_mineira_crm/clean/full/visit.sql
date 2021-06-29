SELECT 
    id, 
    cliente_id AS id_client, 
    ficha_id AS id_form,
    imovel_id AS id_house, 
    solicitacao_id AS id_request,
    usuario_id AS id_user, 
    usuario_validacao_id AS id_user_validation, 
    validacao AS validation_type, 
    CAST(virtual AS BOOLEAN) AS is_virtual, 
    CAST(visita_em AS TIMESTAMP) AS ts_visited, 
    CAST(validado_em AS TIMESTAMP) AS ts_validated, 
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.visita