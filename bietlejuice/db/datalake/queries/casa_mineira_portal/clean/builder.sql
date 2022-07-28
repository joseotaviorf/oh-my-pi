SELECT
    id,
    cidade_id AS id_city,
    nome AS builder_name,
    nome_completo AS builder_full_name,
    slug AS builder_slug_name,
    CAST(total_imoveis AS INT) AS total_houses,
    CAST(total_imoveis_ativos AS INT) AS total_active_houses,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.construtora