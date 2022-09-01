SELECT
    codigo_proposta AS id_proposal,
    codigo_operacao AS id_operation,
    resultado AS analysis_result,
    calc_modelo_def AS model_score,
    calc_decisao_json AS model_metadata,
    TO_TIMESTAMP(REPLACE(instante, '.000', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_operation,
    year,
    month,
    day
FROM
    datalake_velo_neurotech_raw.logs_credit_granting
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
