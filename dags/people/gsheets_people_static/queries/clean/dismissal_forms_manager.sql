SELECT
    email_colabb AS employee_email,
    matricula AS employee_registration,
    tipo_desligamento AS dismissal_type,
    tempo_gestao AS direct_leader_time,
    frequencia_feedback AS feedback_frequency,
    acao_feedback AS feedback_frequency_action,
    preparo_senioridade AS prepared_seniority,
    impacto_direto_entregas AS directly_impacts_deliveries,
    conhecimento_especializado AS specialized_knowledge,
    alteracao_comportamento AS behavior_change,
    pergunta_aberta_1 AS open_question_1,
    pergunta_aberta_2 AS open_question_2,
    reposicao_imediata AS immediate_replacement,
    quem_fara_desligamento AS who_will_dismiss_name,
    quem_respondeu_forms AS manager_email,
    pepa AS people_partner_name,
    diretoria AS employee_board,
    vertical AS employee_vertical,
    cargo AS employee_office,
    departamento AS employee_department,
    centrodecusto AS employee_cost_center,
    diretos AS direct,
    indiretos AS indirect,
    ultimo_perf_review AS last_performance_review,
    penultimo_perf_review AS penultimate_performance_review,
    banda AS employee_band,
    recency,
    maior_fit_cultural AS greater_cultural_fit,
    menor_fit_cultural AS smallest_cultural,
    merged_doc_id_delivery_forms_offboarding_pepa AS doc_id_delivery_forms_offboarding_pepa,
    merged_doc_url_delivery_forms_offboarding_pepa AS doc_url_delivery_forms_offboarding_pepa,
    link_to_merged_doc_delivery_forms_offboarding_pepa AS doc_link_delivery_forms_offboarding_pepa,
    document_merge_status_delivery_forms_offboarding_pepa AS doc_status_merge_status_delivery_forms_offboarding_pepa,
    acao_retencao1 AS retention_action,
    email_pessoal AS employee_personal_email,
    lider_substituto AS substitute_leader_name,
    INT(idadeempresa) AS employee_company_time,
    float(replace(valordosalario, ",", ".")) AS employee_salary,
    INT(qtd_movimentos) AS quantity_movements,
    CASE 
        WHEN acao_retencao = 'Sim'
            THEN TRUE
        ELSE FALSE
    END AS has_retention_action,
    CASE
        WHEN conduta = 'Sim'
            THEN TRUE
        ELSE FALSE
    END AS has_company_values,
    CASE 
        WHEN acompanhamento_pepa = 'Sim'
            THEN TRUE
        ELSE FALSE
    END AS is_people_partner_monitor_dismissal,
    CASE
        WHEN lideranca = 'lider'
            THEN TRUE
        ELSE FALSE
    END AS is_leader,
    INT(idadepessoa) AS employee_age,
    aceitou_retecao AS has_accepted_retention,
    to_date(data_desligamento_inv, 'dd/MM/yyyy') AS dt_dismissal_involuntary,
    to_date(data_retencao, 'dd/MM/yyyy') AS dt_retention,
    data_saida_dp AS dt_effective_dismissal,
    to_date(data_prevista_saida_vol, 'dd/MM/yyyy') AS dt_expected_dismissal,
    to_timestamp(hora_desligamento_inv, 'dd/MM/yyyy HH:mm:ss') AS ts_dismissal_involuntary,
    to_timestamp(data_preenchimento_forms, 'dd/MM/yyyy HH:mm:ss') AS ts_fill_forms,
    ts_load
FROM datalake_gsheets_people_raw.dismissal_forms_manager
WHERE email_colabb != 'E-mail QuintoAndar da pessoa colaboradora'