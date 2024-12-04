SELECT
    CAST(codigo_proposta AS BIGINT) AS id_proposal,
    CAST(codigo_operacao AS BIGINT) AS id_operation,
    year AS year,
    month AS month,
    day AS day
FROM
    datalake_velo_neurotech_pj_raw.logs_pj_scoping_policy
