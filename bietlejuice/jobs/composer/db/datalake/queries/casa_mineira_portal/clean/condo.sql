SELECT
    id,
    logradouro_id AS id_address,
    construtora_id AS id_builder,
    bairro_id AS id_neighborhood,
    nome AS condo_name,
    nome_completo AS condo_full_name,
    slug_completo AS condo_slug_full_name,
    logradouro AS address,
    numero AS address_number,
    cep AS zip_code,
    CAST(latitude AS FLOAT) AS lat,
    CAST(longitude AS FLOAT) AS lng,
    CAST(total_imoveis AS SMALLINT) AS total_houses,
    CAST(total_imoveis_ativos AS SMALLINT) AS total_active_houses,
    CAST(verificado AS BOOLEAN) AS is_verified,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.condominio