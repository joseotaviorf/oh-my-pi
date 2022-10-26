SELECT
    id,
    imovel_id AS id_house,
    usuario_id AS id_user,
    usuario_agendamento_id AS id_user_scheduling,
    forma_entrada AS entry_form,
    local_instalacao AS installation_place,
    tipo AS sign_type,
    CAST(manutencao AS BOOLEAN) AS has_maintenance,
    CAST(placa_exclusiva AS BOOLEAN) AS is_exclusive_sign,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(atualizado_em AS TIMESTAMP) AS ts_updated
FROM 
    datalake_casa_mineira_crm_raw.placa