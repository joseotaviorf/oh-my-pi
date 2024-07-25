SELECT
    CAST(nCodCC AS BIGINT) AS id_account,
    CAST(codigo_pais AS BIGINT) AS id_country,
    CAST(codigo_banco AS BIGINT) AS id_bank,
    codigo_agencia AS id_bank_branch,
    numero_conta_corrente AS bank_account_number,
    bol_instr1 AS invoice_instructions,
    descricao AS description,
    pdv_categoria AS point_of_sale_category,
    tipo AS type,
    tipo_conta_corrente AS bank_account_type,
    user_alt AS alteration_user,
    user_inc AS creation_user,
    nome_gerente AS manager_name,
    endereco AS address,
    numero AS address_number,
    estado AS state,
    bairro AS neighbourhood,
    cidade AS city,
    cep AS zip_code,
    email,
    ddd AS city_code,
    telefone AS phone_number,
    CAST(pdv_dias_venc AS BIGINT) AS point_of_sale_due_days,
    CAST(pdv_limite_pacelas AS BIGINT) AS point_of_sale_installments_limit,
    CAST(pdv_num_parcelas AS BIGINT) AS point_of_sale_installments,
    CAST(pdv_tipo_tef AS BIGINT) AS point_of_sale_tef_type,
    CAST(saldo_inicial AS DOUBLE) AS initial_balance,
    CASE
        WHEN pdv_sincr_analitica = 'S' THEN TRUE
        WHEN pdv_sincr_analitica = 'N' THEN FALSE
        ELSE NULL
    END AS does_point_of_sale_syncs_analytical_mode,
    CASE
        WHEN pdv_enviar = 'S' THEN TRUE
        WHEN pdv_enviar = 'N' THEN FALSE
        ELSE NULL
    END AS is_point_of_sale_omie_pdv,
    CASE
        WHEN nao_resumo = 'S' THEN TRUE
        WHEN nao_resumo = 'N' THEN FALSE
        ELSE NULL
    END AS does_not_display_account_summary,
    CASE
        WHEN nao_fluxo = 'S' THEN TRUE
        WHEN nao_fluxo = 'N' THEN FALSE
        ELSE NULL
    END AS does_not_display_cash_flow,
    CASE
        WHEN inativo = 'S' THEN TRUE
        WHEN inativo = 'N' THEN FALSE
        ELSE NULL
    END AS is_inactive,
    CASE
        WHEN importado_api = 'S' THEN TRUE
        WHEN importado_api = 'N' THEN FALSE
        ELSE NULL
    END AS is_api_imported,
    CASE
        WHEN cobr_sn = 'S' THEN TRUE
        WHEN cobr_sn = 'N' THEN FALSE
        ELSE NULL
    END AS is_able_emit_account_charge,
    CASE
        WHEN bol_sn = 'S' THEN TRUE
        WHEN bol_sn = 'N' THEN FALSE
        ELSE NULL
    END AS is_able_emit_invoice_charge,
    CASE
        WHEN bloqueado = 'S' THEN TRUE
        WHEN bloqueado = 'N' THEN FALSE
        ELSE NULL
    END AS is_blocked,
    TO_DATE(saldo_data, 'dd/MM/yyyy') AS dt_account_balance,
    to_timestamp(concat_ws(' ', data_inc, hora_inc),'dd/MM/yyyy HH:mm:ss') AS ts_created,
    to_timestamp(concat_ws(' ', data_alt, hora_alt),'dd/MM/yyyy HH:mm:ss') AS ts_updated
FROM
    datalake_velo_omie_homolog_raw.bank_account
