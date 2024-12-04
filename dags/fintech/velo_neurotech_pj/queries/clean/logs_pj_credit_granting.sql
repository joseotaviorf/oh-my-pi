SELECT
    codigo_proposta AS id_proposal,
    codigo_operacao AS id_operation,
    year,
    month,
    day
FROM
    datalake_velo_neurotech_pj_raw.logs_pj_credit_granting
