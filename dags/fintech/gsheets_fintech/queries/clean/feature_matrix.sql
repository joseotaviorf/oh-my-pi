SELECT
    CAST(pay_analistas_internos_celula_de_serfin_em_cx AS STRING) AS pay_internal_analysts_scope,
    CAST(pay_bpo_back AS STRING) AS pay_bpo_back_scope,
    CAST(pay_bpo_front AS STRING) AS pay_bpo_front_scope,
    CAST(off_bpo_back AS STRING) AS offboarding_bpo_back_scope,
    CAST(off_bpo_front AS STRING) AS offboarding_bpo_front_scope,
    CAST(onb_bpo_back AS STRING) AS onboarding_bpo_back_scope,
    CAST(onb_bpo_front AS STRING) AS onboarding_bpo_front_scope,
    CAST(reparos_bpo_back AS STRING) AS repairs_bpo_back_scope,
    CAST(reparos_bpo_front AS STRING) AS repairs_bpo_front_scope,
    CAST(csi AS STRING) AS csi_team_scope,
    CAST(ra AS STRING) AS ra_team_scope,
    CAST(mediacao AS STRING) AS mediation_team_scope,
    CAST(spoc AS STRING) AS spoc_team_scope,
    CAST(ferramenta AS STRING) AS tool_system_name,
    CAST(tipo_de_tarefa_feature AS STRING) AS task_feature_type,
    CAST(tipo_de_despesa_bandaid_multa_fatura AS STRING) AS sub_feature_category,
    CAST(despesa AS STRING) AS expense_detail_type,
    CAST(volume_de_uso AS STRING) AS usage_volume_level,
    CAST(impacto AS STRING) AS business_impact_level
FROM
    datalake_gsheets_raw.feature_matrix
