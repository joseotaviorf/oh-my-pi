SELECT
    NULLIF(TRIM(competencia), '') AS competence,
    CAST(NULLIF(TRIM(contrato), '') AS BIGINT) AS id_contract,
    NULLIF(TRIM(tipo_de_erro), '') AS error_type,
    NULLIF(TRIM(erro), '') AS error,
    NULLIF(TRIM(descricao), '') AS description,
    NULLIF(TRIM(valor), '') AS amount,
    NULLIF(TRIM(analise), '') AS analysis,
    NULLIF(TRIM(erro_padrao_quality), '') AS standard_quality_error,
    NULLIF(TRIM(periodo), '') AS period,
    NULLIF(TRIM(correcao), '') AS correction,
    NULLIF(TRIM(ofensor_causa_raiz), '') AS root_cause_offender,
    NULLIF(TRIM(envio_correcao), '') AS correction_sent,
    NULLIF(TRIM(descricao_correcao), '') AS correction_description,
    NULLIF(TRIM(obs), '') AS notes,
    NULLIF(TRIM(time), '') AS team,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.quality_closing_ongoing
