SELECT
    codigo AS id_category,
    categoria_superior AS id_superior_category,
    id_conta_contabil AS id_account,
    codigo_dre AS id_dre,
    descricao AS description,
    descricao_padrao AS default_description,
    natureza AS nature_description,
    tag_conta_contabil AS account_tag,
    descricaoDRE AS dre_description,
    nivelDRE AS dre_level,
    sinalDRE AS dre_sinal,
    CASE
        WHEN conta_despesa = 'S' THEN TRUE
        WHEN conta_despesa = 'N' THEN FALSE
        ELSE NULL
    END AS is_expenses_account,
    CASE
        WHEN conta_receita = 'S' THEN TRUE
        WHEN conta_receita = 'N' THEN FALSE
        ELSE NULL
    END AS is_revenue_account,
    CASE
        WHEN totalizadora = 'S' THEN TRUE
        WHEN totalizadora = 'N' THEN FALSE
        ELSE NULL
    END AS is_totalizer_account,
    CASE
        WHEN transferencia = 'S' THEN TRUE
        WHEN transferencia = 'N' THEN FALSE
        ELSE NULL
    END AS is_transfer_account,
    CASE
        WHEN conta_inativa = 'S' THEN TRUE
        WHEN conta_inativa = 'N' THEN FALSE
        ELSE NULL
    END AS is_account_inactive,
    CASE
        WHEN definida_pelo_usuario = 'S' THEN TRUE
        WHEN definida_pelo_usuario = 'N' THEN FALSE
        ELSE NULL
    END AS is_user_defined,
    CASE
        WHEN nao_exibir = 'S' THEN TRUE
        WHEN nao_exibir = 'N' THEN FALSE
        ELSE NULL
    END AS has_do_not_show_tag,
    CASE
        WHEN totalizaDRE = 'S' THEN TRUE
        WHEN totalizaDRE = 'N' THEN FALSE
        ELSE NULL
    END AS is_dre_totalizer,
    CASE
        WHEN naoExibirDRE = 'S' THEN TRUE
        WHEN naoExibirDRE = 'N' THEN FALSE
        ELSE NULL
    END AS has_dre_do_not_show_tag
FROM
    datalake_velo_omie_homolog_raw.categories
