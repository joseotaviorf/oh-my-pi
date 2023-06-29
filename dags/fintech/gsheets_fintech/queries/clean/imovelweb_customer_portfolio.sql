SELECT
    CAST(NULLIF(_id_sap, '') AS BIGINT) AS sk_sap,
    CAST(REPLACE(REPLACE(REPLACE(NULLIF(_cpf_cnpj, ''), '/',''), '-', ''), '.', '') AS BIGINT) AS document_number,
    NULLIF(_pf_pj, '') AS legal_entity,
    NULLIF(_razao_social, '') AS realestate_name,
    NULLIF(_regiao, '') AS city_group,
    NULLIF(_cidade, '') AS city,
    NULLIF(_bairro, '') AS neighborhood,
    NULLIF(email, '') AS email,
    CAST(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(NULLIF(telefone_1, ''), '/',''), '-', ''), '.', ''), '(', ''), ')', '') AS BIGINT) AS phone_number,
    NULLIF(equipe, '') AS realestate_segmentation,
    NULLIF(integrador, '') AS integrator,
    CAST(REPLACE(REPLACE(NULLIF(_valor_mensal, ''), '.', ''), ',', '.') AS DOUBLE) AS amount,
    CAST(NULLIF(_estoque_concorrencia, '') AS BIGINT) AS competitiors_listings,
    CAST(NULLIF(_listings_aluguel, '') AS BIGINT) AS rent_listings,
    CAST(NULLIF(listings_venda, '') AS BIGINT) AS sale_listings,
    CAST(REPLACE(REPLACE(NULLIF(ticket_medio_rent, ''), '.', ''), ',', '.') AS DOUBLE) AS average_rent,
    CAST(REPLACE(REPLACE(NULLIF(ticket_medio_sale, ''), '.', ''), ',', '.') AS DOUBLE) AS average_sale
FROM
    datalake_gsheets_raw.imovelweb_customer_portfolio;