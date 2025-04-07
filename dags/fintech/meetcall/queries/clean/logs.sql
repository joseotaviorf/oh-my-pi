SELECT
    id_ocorrencia AS id_occurrence,
    id_operador_cyber AS id_operator_cyber,
    id_operador_assessoria AS id_operator_grb,
    id_contrato AS id_contract,
    telefone_acionado AS phone_contacted,
    email_acionado AS email_contacted,
    tabulacao_assessoria AS assessment_tag,
    acao AS action,
    resultado AS result,
    complemento AS complement,
    envio_pesquisa AS survey_sent,
    nota_pesquisa AS survey_score,
    canal AS channel,
    tipo_contato AS contact_type,
    acionamento AS triggered,
    alo,
    cpc,
    tempo_falado AS talk_time,
    data_hora_ocorrencia_inicio AS ts_occurrence_start,
    data_hora_ocorrencia_fim AS ts_occurrence_end,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_meetcall_raw.acoescobranca
WHERE
     MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
