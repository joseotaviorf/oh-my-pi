SELECT
    id,
    logradouro_id AS id_address,
    bairro_id AS id_neighborhood,
    nome AS interest_point_name,
    nome_completo AS interest_point_full_name,
    slug_completo AS interest_point_full_slug_name,
    genero AS gender,
    logradouro AS address,
    numero AS address_number,
    complemento AS complement,
    cep AS zip_code,
    CAST(latitude AS FLOAT) AS lat,
    CAST(longitude AS FLOAT) AS lng,
    CAST(total_imoveis AS INT) AS total_houses,
    CAST(total_imoveis_ativos AS INT) AS total_active_houses,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.ponto_interesse