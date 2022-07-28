SELECT
    atributo_id AS id_attribute,
    imovel_id AS id_house,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM 
    datalake_casa_mineira_crm_raw.imovel_atributo