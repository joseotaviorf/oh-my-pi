SELECT
    NULLIF(TRIM(check_duplicados), '') AS duplicate_check,
    NULLIF(TRIM(categoria_analise), '') AS analysis_category,
    NULLIF(TRIM(periodo_da_analise), '') AS analysis_period,
    CAST(NULLIF(TRIM(contrato), '') AS BIGINT) AS id_contract,
    NULLIF(TRIM(origem_da_demanda), '') AS demand_origin,
    NULLIF(TRIM(descricao_do_problema), '') AS problem_description,
    NULLIF(TRIM(observacoes), '') AS notes,
    NULLIF(TRIM(competencia_do_erro), '') AS error_competence,
    NULLIF(TRIM(id), '') AS id,
    NULLIF(TRIM(check_id), '') AS check_id,
    NULLIF(TRIM(cliente), '') AS client,
    TO_DATE(NULLIF(TRIM(data_de_inclusao), ''), 'dd/MM/yyyy') AS dt_inclusion,
    NULLIF(TRIM(demanda_no_zendesk), '') AS has_zendesk_demand,
    NULLIF(TRIM(ticket_zendesk), '') AS id_ticket_zendesk,
    TO_DATE(NULLIF(TRIM(data_de_criacao), ''), 'dd/MM/yyyy') AS dt_created,
    TO_DATE(NULLIF(TRIM(data_de_resolucao), ''), 'dd/MM/yyyy') AS dt_resolution,
    NULLIF(TRIM(sla), '') AS sla,
    NULLIF(TRIM(sf_pendencia), '') AS sf_pending,
    NULLIF(TRIM(sf_intermitencia_), '') AS sf_intermittency,
    NULLIF(TRIM(sf_causa_raiz_da_intermitencia), '') AS sf_intermittency_root_cause,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.closing_quality
