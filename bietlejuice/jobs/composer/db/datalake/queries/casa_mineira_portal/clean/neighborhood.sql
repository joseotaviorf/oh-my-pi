SELECT
    id,
    cidade_id AS id_city,
    nome AS neighborhood,
    nome_completo AS full_neighborhood,
    slug AS slug_neighborhood,
    nome_correios AS mail_name,
    CAST(total_imoveis AS INT) AS total_house,
    CAST(total_imoveis_ativos AS INT) AS total_active_house,
    CAST(total_condominios AS SMALLINT) AS total_condo,
    CAST(total_pontos_interesse AS SMALLINT) AS total_interest_points,
    CAST(criado_em AS TIMESTAMP) AS ts_created 
FROM
    datalake_casa_mineira_portal_raw.bairro