SELECT
    codigo_proposta AS id_proposal,
    codigo_operacao AS id_operation,
    year,
    month,
    day
FROM
    datalake_velo_neurotech_homolog_raw.logs_credit_granting_pj
