SELECT
    id,
    nome AS attribute_type_name,
    slug AS attribute_type_slug_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.atributo_tipo