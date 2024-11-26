SELECT
    CAST(codigo_proposta AS BIGINT) AS id_proposal,
    CAST(codigo_operacao AS BIGINT) AS id_operation,
    year AS year,
    month AS month,
    day AS day
FROM
    datalake_velo_neurotech_homolog_raw.logs_scoping_policy_homolog
