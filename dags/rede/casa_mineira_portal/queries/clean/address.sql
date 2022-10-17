SELECT
    id,
    cidade_id AS id_city,
    nome AS address,
    nome_completo AS full_address,
    slug AS slug_address,
    CAST(total_imoveis AS INT) AS total_houses,
    CAST(total_imoveis_ativos AS INT) AS total_active_houses,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.logradouro