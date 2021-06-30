SELECT
    id,
    cidade_id AS id_city,
    nome AS neighborhood_name,
    slug AS neighborhood_slug_name,
    slug_completo AS neighborhood_full_slug_name,
    CAST(prioridade AS BOOLEAN) AS is_priority,
    CAST(visibilidade AS BOOLEAN) AS is_visible,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.bairro
