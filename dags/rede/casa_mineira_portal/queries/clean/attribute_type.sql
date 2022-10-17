SELECT
    id,
    nome AS attribute_name,
    nome_completo AS attribute_full_name,
    slug AS attribute_slug_name,
    ordem AS attribute_order,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.atributo_tipo