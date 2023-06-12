SELECT
    act_id AS id_activity,
    CAST(cid AS BIGINT) AS id_contract,
    CAST(uid AS BIGINT) AS id_user,
    token,
    type,
    sugestao_melhorias AS improvement_suggestions,
    descricao_nivel_satisfacao AS satisfation_level_description,
    motivo_satisfacao AS satisfation_level_reason,
    CAST(nivel_satisfacao AS INTEGER) AS satisfation_level,
    CAST(is_solved AS BOOLEAN) AS is_solved,
    TO_TIMESTAMP(submitted_at, 'dd/MM/yyyy HH:mm:ss') AS ts_submitted,
    TIMESTAMP(ts_load) AS ts_load
FROM
    datalake_gsheets_raw.csat_reembolso_true