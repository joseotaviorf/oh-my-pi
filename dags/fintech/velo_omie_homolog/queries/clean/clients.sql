SELECT
    codigo_cliente_omie AS id_client,
    codigo_cliente_integracao AS id_client_integration,
    CAST(codigo_banco AS BIGINT) AS id_bank,
    agencia AS id_bank_branch,
    tipo_assinante AS id_type_signer,
    razao_social AS corporate_name,
    cnpj_cpf AS client_cpf_cnpj,
    nome_fantasia AS name_doing_business_as,
    telefone1_ddd AS phone1_city_codes,
    telefone1_numero AS phone1_number,
    telefone2_ddd AS phone2_city_codes,
    telefone2_numero AS phone2_number,
    fax_ddd AS fax_city_codes,
    fax_numero AS fax_number,
    contato AS name_person_contact,
    endereco AS address,
    endereco_numero AS address_number,
    bairro AS address_neighborhood,
    estado AS address_state,
    cidade AS address_city,
    cidade_ibge AS address_city_ibge_code,
    cep AS address_zipcode,
    codigo_pais AS address_country_code,
    complemento AS address_complement,
    email,
    inscricao_estadual AS state_registration,
    inscricao_municipal AS city_registration,
    tipo_atividade AS business_activity_type,
    cnae,
    transform(tags, x -> x['tag']) AS tags,
    conta_corrente AS bank_account_number,
    doc_titular AS cpf_cnpj_account_owner,
    nome_titular AS name_account_owner,
    uAlt AS alteration_user,
    uInc AS creation_user,
    CASE
        WHEN optante_simples_nacional = 'S' THEN TRUE
        WHEN optante_simples_nacional = 'N' THEN FALSE
        ELSE NULL
    END AS has_simples_tax_regime,

    CASE
        WHEN pessoa_fisica = 'S' THEN TRUE
        WHEN pessoa_fisica = 'N' THEN FALSE
        ELSE NULL
    END AS is_natural_person,
    CASE
        WHEN exterior = 'S' THEN TRUE
        WHEN exterior = 'N' THEN FALSE
        ELSE NULL
    END AS is_foreign,
    CASE
        WHEN cImpAPI = 'S' THEN TRUE
        WHEN cImpAPI = 'N' THEN FALSE
        ELSE NULL
    END AS is_api_imported,
    CASE
        WHEN bloquear_faturamento = 'S' THEN TRUE
        WHEN bloquear_faturamento = 'N' THEN FALSE
        ELSE NULL
    END AS is_billing_blocked,
    CASE
        WHEN inativo = 'S' THEN TRUE
        WHEN inativo = 'N' THEN FALSE
        ELSE NULL
    END AS is_inactive,
    CASE
        WHEN gerar_boletos = 'S' THEN TRUE
        WHEN gerar_boletos = 'N' THEN FALSE
        ELSE NULL
    END AS has_default_generate_bill,
    CASE
        WHEN transf_padrao = 'S' THEN TRUE
        WHEN transf_padrao = 'N' THEN FALSE
        ELSE NULL
    END AS is_default_bank_transfer,
    to_timestamp(concat_ws(' ', dInc, hInc),'dd/MM/yyyy HH:mm:ss') AS ts_created,
    to_timestamp(concat_ws(' ', dAlt, hAlt),'dd/MM/yyyy HH:mm:ss') AS ts_updated
FROM
    datalake_velo_omie_homolog_raw.clients
