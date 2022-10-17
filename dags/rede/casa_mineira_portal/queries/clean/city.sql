SELECT
    id,
    uf_id AS id_uf,
    nome AS city_name,
    nome_completo AS city_full_name,
    slug AS city_slug_name,
    CAST(total_imoveis AS INT) AS total_houses,
    CAST(total_imoveis_ativos AS INT) AS total_active_houses,
    CAST(total_bairros AS INT) AS total_neighborhoods,
    CAST(total_logradouros AS INT) AS total_addresses,
    CAST(total_condominios AS INT) AS total_condo,
    CAST(total_construtoras AS INT) AS total_builders,
    CAST(total_pontos_interesse AS INT) AS total_interest_points,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.cidade