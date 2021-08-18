SELECT 
    id, 
    usuario_id AS id_user, 
    imovel_id AS id_house, 
    cliente_id AS id_client, 
    comprador_email AS buyer_email,
    comprador_telefone AS buyer_phone_number, 
    CAST(porcentagem_comissao_captacao AS FLOAT) AS acquisition_brokerage_fee,
    CAST(preco_anunciado AS FLOAT) AS listing_sale_price,
    CAST(preco_negociado AS FLOAT) AS sale_price_agreed,
    CAST(comissao_negociada AS FLOAT) AS brokarage_fee_agreed,
    bonus,
    CAST(vendido_em AS TIMESTAMP) AS ts_sold,
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(atualizado_em AS TIMESTAMP) AS ts_updated
FROM 
    datalake_casa_mineira_crm_raw.venda