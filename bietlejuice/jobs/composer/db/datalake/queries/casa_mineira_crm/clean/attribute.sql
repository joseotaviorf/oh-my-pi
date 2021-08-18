SELECT
    id,
    atributo_tipo_id AS id_attribute_type,
    nome AS attribute_name, 
    nome_completo AS attribute_full_name,
    slug AS attribute_slug_name,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.atributo