SELECT
    id,
    tipo_id AS id_attribute_type,
    nome AS attribute_name,
    nome_completo AS attribute_full_name,
    nome_completo_preposto AS attribute_full_name_prepositional,
    slug AS attribute_slug_name,
    finalidade AS attribute_goal,
    CAST(primario AS BOOLEAN) AS is_primary,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.atributo