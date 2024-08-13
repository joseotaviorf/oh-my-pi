SELECT
    CAST(id AS BIGINT) AS id_activations,
    id_airtable_record,
    status_ativacao AS activation_status,
    estado_de_atuacao AS actuation_state,
    nome_completo AS agent_complete_name,
    CAST(creci AS BIGINT) AS agent_creci,
    email AS agent_email,
    telefone AS agent_phone_number,
    regiao_escolhida AS chosen_region,
    cpf,
    desistencia_motivo AS giving_up_reason,
    modalidade AS model,
    lead_original AS original_lead,
    regiao AS region,
    1_opcao AS region_first_option,
    2_opcao AS region_second_option,
    CAST(aviso_ativacao AS BOOLEAN) AS has_activation_notification,
    CAST(email_boasvindas AS BOOLEAN) AS has_welcome_email,
    CAST(whats_pocket AS BOOLEAN) AS has_whats_pocket,
    TO_DATE(confirmacao_de_agenda, 'yyyy-MM-dd') AS dt_agency_confirmation,
    TO_DATE(data_de_nascimento, 'yyyy-MM-dd') AS dt_birth,
    TO_DATE(envio_de_contrato, 'yyyy-MM-dd') AS dt_contract_sent,
    TO_DATE(data_desistencia, 'yyyy-MM-dd') AS dt_giving_up,
    TO_DATE(criacao_id, 'yyyy-MM-dd') AS dt_id_creation,
    TO_DATE(solicitacao_jitex, 'yyyy-MM-dd') AS dt_jitex_requested,
    TO_DATE(recebimento_kit, 'yyyy-MM-dd') AS dt_kit_received,
    TO_DATE(assinatura, 'yyyy-MM-dd') AS dt_signed,
    TO_DATE(semana_de_credenciamento, 'yyyy-MM-dd') AS dt_week_accreditated,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.activations
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}