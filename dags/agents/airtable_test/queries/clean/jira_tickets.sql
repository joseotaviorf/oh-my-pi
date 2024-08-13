SELECT
    id AS id_airtable_record,
    CAST(id_do_corretor AS BIGINT) AS id_agent,
    CAST(ql_id_do_agente AS BIGINT) AS id_ql_agent,
    issue_key AS id_issue,
    ativos AS activated,
    cpf_from_ativos AS cpf,
    descricao AS description,
    open_in_jira,
    descredenciamento_permanente AS permanent_deaccreditation,
    ql_nome_completo_do_corretor AS ql_agent_complete_name,
    ql_seguimento_do_corretor AS ql_agent_line,
    ql_regiao_de_atuacao AS ql_agent_region,
    ql_tipo_agent AS ql_agent_type,
    ql_motivo_descredenciamento AS ql_deaccreditation_reason,
    ql_tipo_de_solicitacao AS ql_solicitation_type,
    ql_tipo_de_suspensao AS ql_suspension_type,
    responsavel AS responsible,
    resumo AS summary,
    TO_DATE(ql_data_inicial, 'yyyy-MM-dd') AS dt_begin,
    TO_DATE(data_descredenciamento,'yyyy-MM-dd') AS dt_deaccreditated,
    TO_DATE(data_retorno_descred,'yyyy-MM-dd') AS dt_deaccreditation_return,
    TO_DATE(ql_data_final, 'yyyy-MM-dd') AS dt_end,
    TO_TIMESTAMP(created) AS ts_created,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.jira_tickets
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}