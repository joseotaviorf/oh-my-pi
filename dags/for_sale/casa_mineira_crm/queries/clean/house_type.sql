SELECT
    id,
    nome AS house_type_name,
    nome_plural AS house_type_plural_name, 
    slug AS house_type_slug_name,
    ordem AS house_type_order,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.tipo