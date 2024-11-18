SELECT 
    aes.source_name,
    ae.id AS id_rh_accounting_entry,
    p.id_external,
    ae.id_payee,
    ae.locale AS city_group,
    ae.description,
    ae.source_bill_item,
    CASE
        WHEN ae.source_bill_item in
            ('valorFixoPorIndicacaoDeImovelForSale',
            'valorFixoPorIndicacaoDeImovel',
            'valorFixoPorIndicacaoDeImovelManual') THEN 'Commission Listing'
        WHEN ae.source_bill_item in
            ('porcentagem Por Indicacao De Imovel Manual',
            'porcentagemPorIndicacaoDeImovelManual',
            'porcentagemPorIndicacaoDeImovel',
            'valorFixoPorLocacaoDeImovelManual',
            'valorFixoPorLocacaoDeImovel') THEN 'Commission Rent'
        WHEN ae.source_bill_item IN
            ('valorFixoPorVendaDeImovelManual',
            'valorFixoPorVendaDeImovel',
            'comissaoSobreImovelVendido',
            'valorFixoPorVendaDeImovelForSale') THEN 'Commission Sale'
        WHEN ae.source_bill_item in
            ('comissaoUnicaSobreAfiliadoIndicado',
            'comissaoSobreAfiliadoIndicado') THEN 'Commission MGM'
        ELSE ae.source_bill_item
    END AS commission_type,
    ae.cost_center_code,
    CASE
        WHEN ae.id_source = 1 THEN 'Indica Aí - General'
        WHEN ae.id_source IN (2,5) THEN 'Indica Aí - Agents'
        WHEN ae.id_source = 3 THEN 'Doorman'
        WHEN ae.id_source = 4 THEN 'B2B'
        ELSE 'Not Mapped'
    END AS mkt_origin,
    ae.due_amount AS cost,
    CAST(DATE_FORMAT(ae.dt_occurrence, 'yyyyMMdd') AS BIGINT) AS dt_transaction
FROM
    datalake_robin_hood_clean.accounting_entry AS ae
JOIN
    datalake_robin_hood_clean.payee AS p
    ON ae.id_payee = p.id
JOIN 
    datalake_robin_hood_clean.accounting_entry_source aes
    ON ae.id_source = aes.id
WHERE 
    ae.description NOT LIKE '%que não foi enviada%'
    AND ae.dt_occurrence >= DATE('2020-01-01')
    AND LOWER(aes.source_name) IN ('indica aí', 'indica aí agents', 'porteiros')
GROUP BY ALL