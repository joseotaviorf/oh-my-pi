SELECT
    id_airtable_record,
    CAST(ql_id_do_agente AS BIGINT) AS id_agent,
    issue_key AS id_issue,
    departamento AS department,
    descricao AS description,
    ql_nome_completo_do_corretor AS ql_agent_complete_name,
    ql_regiao_de_atuacao AS ql_agent_region,
    ql_seguimento_do_corretor AS ql_agent_segment,
    ql_qual_ocorrencia_deseja_informar_corretor_presencial_virtual AS ql_ocorrency_category,
    ql_tipo_de_ocorrencia AS ql_occorency_type,
    ql_resolucao AS ql_resolution,
    ql_ticket_e_de AS ql_ticket_from,
    responsavel AS responsible,
    resumo AS summary,
    ql_ql_quem_esta_fazendo_essa_reclamacaodenunciasolicitacao AS who_is_complaining,
    TO_TIMESTAMP(created) AS ts_created,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.cr_occurrences
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}