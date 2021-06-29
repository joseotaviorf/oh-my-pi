SELECT 
    id, 
    contato_id AS id_contact, 
    usuario_validacao_id AS id_user_validation,
    validacao AS validation_type, 
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(visita_em AS TIMESTAMP) AS ts_visited, 
    CAST(validado_em AS TIMESTAMP) AS ts_validated
FROM 
    datalake_casa_mineira_crm_raw.visita_solicitacao
