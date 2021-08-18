SELECT 
    id, 
    uf_id AS id_uf,
    nome AS city_name, 
    slug AS city_slug_name, 
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.cidade 