SELECT
    id,
    email,
    total_venda AS total_sales_range,
    total_aluguel AS total_rent_range,
    CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
    datalake_casa_mineira_portal_raw.captacao_imobiliaria