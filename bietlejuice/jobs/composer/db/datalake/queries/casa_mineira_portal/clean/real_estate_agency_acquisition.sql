SELECT
    id,
    email,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.captacao_imobiliaria