SELECT
    id,
    imovel_id AS id_house,
    avaliado_por AS evaluated_by,
    criado_por AS created_by,
    CAST(preco_avaliacao AS FLOAT) AS evalutation_sale_price,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_crm_raw.usuario_avaliacao_imovel