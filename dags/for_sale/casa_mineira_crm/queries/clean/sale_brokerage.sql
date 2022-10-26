SELECT  
    id, 
    venda_id AS id_sale, 
    usuario_id AS id_user, 
    tipo AS sale_type, 
    subtipo AS sale_subtype, 
    status AS sale_status, 
    escritorio AS office,
    CAST(porcentagem_comissao_tipo AS FLOAT) AS percentage_brokerage_type,
    CAST(porcentagem_comissao_total AS FLOAT) AS percentage_total_brokerage,
    CAST(comissao_bruta AS FLOAT) AS gross_brokerage_value,
    CAST(comissao_impostos AS FLOAT) AS taxes_brokerage_value,
    CAST(comissao_liquida AS FLOAT) AS net_brokerage_value

FROM 
    datalake_casa_mineira_crm_raw.venda_comissao