SELECT 
    id,
    imovel_id AS id_house,
    usuario_atendimento_id AS id_user_attendance,
    usuario_confirmacao_id AS id_user_confirmation,
    tipo_id AS id_type,
    `status` AS change_request_status,
    CAST(aceito_em AS TIMESTAMP) AS ts_accepted,
    CAST(recusado_em AS TIMESTAMP) AS ts_rejected,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.solicitacao_alteracao