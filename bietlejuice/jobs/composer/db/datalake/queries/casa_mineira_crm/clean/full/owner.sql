SELECT 
    id, 
    imovel_id AS id_house, 
    tipo AS owner_type, 
    bairro AS owner_neighborhood, 
    cidade AS owner_city, 
    uf AS owner_uf, 
    cep AS owner_zip_code, 
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.proprietario 
