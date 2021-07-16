SELECT
    id, 
    cliente_id AS id_client,
    imovel_id AS id_house,
    midia_id AS id_media, 
    origem_id AS id_origin, 
    usuario_atendimento_id AS id_user_attendance, 
    usuario_encaminhamento_id AS id_user_forwarding,
    usuario_rejeicao_id AS id_user_rejection,
    criado_por AS created_by,
    email,
    telefone AS phone_number, 
    token,
    CAST(automatizado AS BOOLEAN) AS is_automated,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(atendimento_em AS TIMESTAMP) AS ts_attended,
    CAST(rejeitado_em AS TIMESTAMP) AS ts_rejected
FROM 
    datalake_casa_mineira_crm_raw.contato