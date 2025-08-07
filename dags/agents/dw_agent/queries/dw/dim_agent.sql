SELECT
    du.dados_agente_id AS sk_agent,
    du.id AS id_user,
    du.nome AS name,
    du.cpf AS cpf,
    du.rg AS rg,
    du.sexo AS sex,
    du.email,
    du.email_alternativo AS alternative_email,
    du.telefone_principal AS main_phone_number,
    du.endereco AS address,
    du.numero AS number,
    du.complemento AS complement,
    du.bairro AS neighborhood,
    du.cep,
    du.cidade AS city,
    du.estado_nome AS state_name,
    du.estado_abreviacao AS state_abbreviation,
    du.country_code,
    wd.contract_name AS work_contract_name,
    NULLIF(wd.3p_partner, '') AS rede_partner,
    at.types AS agent_type,
    du.dadosagente_perfil AS agent_profile,
    du.dadosagente_numero_creci AS agent_creci,
    BOOLEAN(du.active) AS is_user_active,
    BOOLEAN(du.bloqueado) AS is_blocked,
    BOOLEAN(du.dadosafiliado_ativo) AS is_affiliate_active,
    BOOLEAN(du.dadosagente_ativo) AS is_agent_active,
    BOOLEAN(du.dadosfotografo_ativo) AS is_photographer_active,
    BOOLEAN(du.inquilino) AS is_tenant,
    du.is_sale_agent,
    du.is_rent_agent,
    tqc.id_agent IS NOT NULL AND tqc.is_currently_active AS is_tqc_3p_agent,
    wd.is_3p_contract AS is_rede_agent,
    du.data_nascimento AS dt_birth,
    du.criado_em AS ts_created,
    du.atualizado_em AS ts_updated,
    NOW() AS ts_load
FROM
    dw_public.dim_user AS du
JOIN
    datalake_ebdb_clean.agent_data AS ad
        ON du.dados_agente_id = ad.id
LEFT JOIN
    datalake_ebdb_work_contract.work_contract AS wd
        ON wd.id = ad.id_work_contract
LEFT JOIN
    datalake_ebdb_clean.agent_data_types AS at 
        ON at.id_agent_data = du.dados_agente_id
LEFT JOIN
    datalake_gsheets_clean.agents_3p_tqc AS tqc
        ON tqc.id_agent = du.dados_agente_id
WHERE
    dados_agente_id IS NOT NULL
QUALIFY -- There are extremely few duplicate rows on agent_data_types (12/16595 at the moment of writing). This is to get rid of them.
    ROW_NUMBER() OVER(PARTITION BY du.dados_agente_id ORDER BY at.types) = 1