SELECT
    id,
    nome AS change_request_type_name,
    prioridade AS priority,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.solicitacao_alteracao_tipo