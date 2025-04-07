SELECT
    codigo_proposta AS id_proposal,
    codigo_operacao AS id_operation,
    CAST(CAST(prop_num_proposta AS DOUBLE) AS INT) AS proposal_number,
    TO_TIMESTAMP(REPLACE(instante, '.000', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_operation,
    year,
    month,
    day
FROM
    datalake_velo_neurotech_pj_raw.logs_pj_credit_granting
