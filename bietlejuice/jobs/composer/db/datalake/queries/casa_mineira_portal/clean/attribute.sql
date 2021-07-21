SELECT
    id,
    atributo_tipo_id AS id_attribute_type,
    nome AS attribute_name,
    slug AS attribute_slug_name,
    slug_completo AS attribute_slug_full_name,
    finalidade AS attribute_goal,
    CAST(primario AS BOOLEAN) AS is_primary,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.atributo