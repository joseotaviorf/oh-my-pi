SELECT
    id_do_corretor AS id_agent,
    ql_id_do_agente AS id_ql_agent,
    issue_key AS id_issue,
    ativados_sale AS activated_sale,
    descricao AS description,
    open_in_jira,
    ql_nome_completo_do_corretor AS ql_agent_complete_name,
    ql_seguimento_do_corretor AS ql_agent_line,
    ql_regiao_de_atuacao AS ql_agent_region,
    ql_tipo_agent AS ql_agent_type,
    ql_motivo_descredenciamento AS ql_deaccreditation_reason,
    ql_tipo_de_solicitacao AS ql_solicitation_type,
    responsavel AS responsible,
    resumo AS summary,
    TO_DATE(created,'yyyy-MM-dd') AS dt_created,
    TO_DATE(data_descredenciamento,'yyyy-MM-dd') AS dt_deaccreditated,
    TO_DATE(data_retorno_descred,'yyyy-MM-dd') AS dt_deaccreditation_return,
    year,
    month,
    day
FROM
    datalake_airtable_raw.jira_tickets
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}