SELECT 
    id,
    construtora_id AS id_builder,
    bairro_id AS id_neighborhood,
    nome AS condo_name,
    nome_completo AS condo_full_name,
    slug AS condo_slug_name,
    slug_completo AS condo_slug_full_name,
    logradouro AS address,
    numero AS address_number,
    cep AS zip_code,
    CAST(latitude AS FLOAT) AS lat,
    CAST(longitude AS FLOAT) AS lng,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.condominio