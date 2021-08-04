WITH user_dates (
    SELECT
        u.id,
        MIN(b.ts_created) AS ts_first_booking,
        -- TODO [ODS] the value for status should be Cancelado instead of Canceled
        MIN(if(b.status != 'Canceled', b.ts_created, NULL)) AS ts_first_booking_confirmed,
        MIN(v.dt_visit) AS dt_first_visit,
        -- TODO [ODS] the value for status should be Cancelado instead of Canceled
        MIN(if(b.status != 'Canceled', v.dt_visit, NULL)) AS dt_first_visit_confirmed,
        MIN(pp.ts_created) AS ts_first_pre_proposal,
        MIN(p.ts_created) AS ts_first_proposal_accepted,
        MIN(c.ts_created) AS ts_first_contract,
        MIN(c.ts_signed) AS ts_first_signed_contract
    FROM datalake_ebdb_user.user u
    LEFT JOIN datalake_booking.booking b
        on b.id_visitor = u.id
    LEFT JOIN datalake_ebdb_clean.visit v
        on v.id = b.id_visit
    LEFT JOIN datalake_ebdb_clean.rent_flow rf
        on rf.id = b.id_rent_flow
    LEFT JOIN datalake_ebdb_clean.pre_proposal pp
        on rf.id_client = pp.id_user
    LEFT JOIN datalake_ebdb_clean.proposal p
        on p.id_pre_proposal = pp.id
    LEFT JOIN datalake_ebdb_clean.contract c
        on c.id_proposal = p.id
    GROUP BY u.id
),
booking_counts AS (
    SELECT
        id_visitor,
        CAST(COUNT(1) AS INTEGER) AS visits_booked,
        CAST(SUM(if(is_visit_completed, 1, 0)) AS INTEGER) AS visits_realized,
        CAST(SUM(if(visit_fup IS NOT NULL, 1, 0)) AS INTEGER) AS visits_expected_to_happen
    FROM datalake_booking.booking
    GROUP BY id_visitor
 )
SELECT -- [ODS] This table was migrated FROM ODS flow and needs a future refactoring to remove castings and renamings
    u.id AS sk_user,
    COALESCE(CAST(date_format(ad.ts_doorman_joined, 'yyyyMMdd') AS bigint), -1) AS sk_doorman_joined_date,
    u.id,
    CAST(u.id_agent AS INTEGER) AS dados_agente_id,
    CAST(u.id_photographer_data AS INTEGER) AS dados_fotografo_id,
    CAST(u.id_sales_rep AS INTEGER) AS dados_vendedor_id,
    CAST(u.id_affiliates AS INTEGER) AS dados_afiliado_id,
    CAST(u.id_facebook AS VARCHAR(255)) AS facebook_id,
    CAST(u.id_linkedin AS VARCHAR(255)) AS linkedin_id,
    NULLIF(CAST(u.id_google AS VARCHAR(255)), '') AS google_id,
    CAST(u.is_active AS INTEGER) AS active,
    CAST(u.is_blocked AS INTEGER) AS bloqueado,
    CAST(ad.is_active AS INTEGER) AS dadosafiliado_ativo,
    CAST(ag.is_active AS INTEGER) AS dadosagente_ativo,
    CAST(p.is_active AS INTEGER) AS dadosfotografo_ativo,
    CAST(COALESCE(ad.is_doorman_affiliate, false) AS INTEGER) AS flg_doorman_affiliate,
    CAST(CAST(u.is_tenant AS INTEGER) AS VARCHAR(10)) AS inquilino,
    ag.is_sale_agent,
    ag.is_rent_agent,
    CAST(u.bank_another_holder AS INTEGER) AS dadosbancarios_outro_titular,
    CAST(CAST(u.has_house AS INTEGER) AS VARCHAR(10)) AS tem_imovel,
    CAST(CAST(u.has_tenant_app AS INTEGER) AS VARCHAR(10)) AS tem_app_inquilino,
    CAST(CAST(u.has_active_contract AS INTEGER) AS VARCHAR(10)) AS tem_contrato_ativo,
    CAST(u.has_accepted_sms AS INTEGER) AS aceita_sms,
    NULLIF(CAST(LEFT(u.name, 200) AS VARCHAR(255)), '') AS nome,
    NULLIF(u.cpf, '') AS cpf,
    u.rg,
    u.gender AS sexo,
    NULLIF(u.email, '') AS email,
    NULLIF(u.alternative_email, '') AS email_alternativo,
    NULLIF(u.main_phone, '') AS telefone_principal,
    NULLIF(u.address, '') AS endereco,
    NULLIF(u.number, '') AS numero,
    NULLIF(u.complement, '') AS complemento,
    NULLIF(u.neighborhood, '') AS bairro,
    NULLIF(u.zip_code, '') AS cep,
    NULLIF(u.city, '') AS cidade,
    s.name AS estado_nome,
    s.abbreviation AS estado_abreviacao,
    u.admin_type AS tipo_admin,
    b.code AS dadosbancarios_banco_codigo,
    b.name AS dadosbancarios_banco,
    u.bank_agency AS dadosbancarios_agencia,
    u.bank_account AS dadosbancarios_conta_corrente,
    u.bank_cpf_cnpj AS dadosbancarios_cpf_cnpj,
    u.bank_name AS dadosbancarios_nome,
    u.bank_account_type AS dadosbancarios_tipo_conta,
    ag.profile AS dadosagente_perfil,
    ag.creci_number AS dadosagente_numero_creci,
    p.contract_type AS dadosfotografo_tipo_contrato,
    ad.work_city AS dadosafiliado_cidade_atuacao,
    ad.payment_preference AS dadosafiliado_preferencia_pagamento,
    NULLIF(ad.creci_number, '') AS dadosafiliado_numero_creci,
    ad.last_week_balance_communication AS dadosafiliado_semana_ultima_comunicacao_balanco,
    b_counts.visits_booked,
    b_counts.visits_realized,
    b_counts.visits_expected_to_happen,
    u.dt_birth AS data_nascimento,
    CAST(user_dates.dt_first_visit AS TIMESTAMP) AS first_visit_date,
    CAST(user_dates.dt_first_visit_confirmed AS TIMESTAMP) AS first_visit_confirmed_date,
    u.ts_click_anuncie AS data_clickanuncie,
    p.ts_contract_started AS dadosfotografo_inicio_contrato,
    sr.ts_contract_started AS dadosvendedor_inicio_contrato,
    ad.ts_first_operation_start AS dadosafiliado_inicio_atuacao,
    user_dates.ts_first_booking AS first_booking_date,
    user_dates.ts_first_booking_confirmed AS first_booking_confirmed_date,
    user_dates.ts_first_pre_proposal AS first_pre_proposal_date,
    user_dates.ts_first_proposal_accepted AS first_proposal_accepted_date,
    user_dates.ts_first_contract AS first_contract_date,
    user_dates.ts_first_signed_contract AS first_signed_contract,
    u.ts_first_document_sent AS first_dt_document_sent,
    u.ts_last_document_sent AS last_dt_document_sent,
    u.ts_first_sent_to_insurance AS first_dt_sent_to_insurance,
    u.ts_created AS criado_em,
    u.ts_updated AS atualizado_em,
    CAST(NULL AS VARCHAR(255)) AS network, -- [ODS] just to match ODS original table / Remove after ODS migration
    NOW() AS load_timestamp
FROM datalake_ebdb_user.user u
INNER JOIN user_dates user_dates
    on user_dates.id = u.id
LEFT JOIN booking_counts b_counts
    on b_counts.id_visitor = u.id
LEFT JOIN datalake_ebdb_clean.state s
    on s.id = u.id_state
LEFT JOIN datalake_ebdb_user.agent_data ag
    on ag.id = u.id_agent
LEFT JOIN datalake_ebdb_clean.bank b
    on b.id = u.id_bank
LEFT JOIN datalake_ebdb_clean.photographer_data p
    on p.id = u.id_photographer_data
LEFT JOIN datalake_ebdb_clean.sales_rep sr
    on sr.id = u.id_sales_rep
LEFT JOIN datalake_ebdb_user.affiliate_data ad
    on ad.id = u.id_affiliates
