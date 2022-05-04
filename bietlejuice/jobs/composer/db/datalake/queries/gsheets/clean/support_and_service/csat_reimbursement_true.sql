SELECT
    token,
    CAST(cid AS BIGINT) AS cid,
    CAST(uid AS BIGINT) AS uid,
    type,
    sugestao_melhorias AS improvement_suggestions,
    descricao_nivel_satisfacao AS satisfation_level_description,
    motivo_satisfacao AS satisfation_level_reason,
    CAST(nivel_satisfacao AS INTEGER) AS satisfation_level,
    TO_TIMESTAMP(submitted_at, 'dd/MM/yyyy HH:mm:ss') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_reembolso_true