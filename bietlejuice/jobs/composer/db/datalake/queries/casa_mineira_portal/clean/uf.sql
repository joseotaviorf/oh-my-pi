SELECT
    id,
    nome AS uf_name,
    slug_completo AS uf_full_name,
    sigla AS uf_initials,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.uf