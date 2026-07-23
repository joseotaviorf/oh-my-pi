WITH 
commission_costs AS (
    SELECT 
        ae.source_name,
        'commission_costs' AS cost_type,
        ae.id AS id_rh_accounting_entry,
        ae.id_external,
        ae.id_payee,
        ae.locale AS city_group,
        ae.description,
        ae.source_bill_item,
        CASE
            WHEN ae.source_bill_item IN (
                'valorFixoPorIndicacaoDeImovelForSale',
                'valorFixoPorIndicacaoDeImovel',
                'valorFixoPorIndicacaoDeImovelManual'
            ) THEN 'Commission Listing'
            WHEN ae.source_bill_item IN (
                'porcentagem Por Indicacao De Imovel Manual',
                'porcentagemPorIndicacaoDeImovelManual',
                'porcentagemPorIndicacaoDeImovel',
                'valorFixoPorLocacaoDeImovelManual',
                'valorFixoPorLocacaoDeImovel'
            ) THEN 'Commission Rent'
            WHEN ae.source_bill_item IN (
                'valorFixoPorVendaDeImovelManual',
                'valorFixoPorVendaDeImovel',
                'comissaoSobreImovelVendido',
                'valorFixoPorVendaDeImovelForSale'
            ) THEN 'Commission Sale'
            WHEN ae.source_bill_item IN (
                'comissaoUnicaSobreAfiliadoIndicado',
                'comissaoSobreAfiliadoIndicado'
            ) THEN 'Commission MGM'
            ELSE ae.source_bill_item
        END AS commission_type,
        CASE 
            WHEN ae.source_bill_item IN (
                'comissaoUnicaSobreAfiliadoIndicado',
                'comissaoSobreAfiliadoIndicado'
            ) THEN 'acquisition' 
            ELSE 'engagement' 
        END AS vertical,
        ae.cost_center_code,
        CASE
            WHEN ae.id_source = 1 THEN 'Indica Aí - General'
            WHEN ae.id_source IN (2, 5) THEN 'Indica Aí - Agents'
            WHEN ae.id_source = 3 THEN 'Doorman'
            WHEN ae.id_source = 4 THEN 'B2B'
            ELSE 'Not Mapped'
        END AS company_report_origin,
        CASE 
            WHEN ae.cost_center_code IN ('C046', 'S01305', 'S02305') THEN 'sale' 
            ELSE 'rent' 
        END AS business_context,
        ae.dt_occurrence AS dt_cost,
        SUM(ae.due_amount) AS total_costs,
        YEAR(ae.dt_occurrence) AS year,
        MONTH(ae.dt_occurrence) AS month,
        DAY(ae.dt_occurrence) AS day
    FROM
        datalake_robin_hood.accounting_entry AS ae
    WHERE 
        ae.description NOT LIKE '%que não foi enviada%'
        AND CAST(ae.dt_occurrence AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
        AND LOWER(ae.source_name) IN ('indica aí', 'indica aí agents', 'porteiros')
    GROUP BY ALL
),
manual_tax AS (
    SELECT
        aes.source_name,
        'manual_tax' AS cost_type,
        NULL AS id_rh_accounting_entry,
        NULL AS id_external,
        t.id_payee,
        tr.locale AS city_group,
        NULL AS description,
        NULL AS source_bill_item,
        'IRRF' AS commission_type,
        'engagement' AS vertical,
        tr.cost_center_code,
        CASE 
            WHEN LOWER(aes.source_name) = 'porteiros' THEN 'Doorman'
            WHEN LOWER(aes.source_name) = 'indica aí agents' THEN 'Indica Aí - Agents'
            WHEN LOWER(aes.source_name) = 'indica aí' THEN 'Indica Aí - General'
            ELSE NULL
        END AS company_report_origin,
        CASE 
            WHEN tr.cost_center_code IN ('C023', 'R01305', 'R02305') THEN 'rent' 
            ELSE 'sale' 
        END AS business_context,
        TO_DATE(CAST(accounting_year_month AS VARCHAR(6)) || '01', 'yyyyMMdd') AS dt_cost, 
        SUM(tr.amount) AS total_costs,
        YEAR(TO_DATE(CAST(accounting_year_month AS VARCHAR(6)) || '01', 'yyyyMMdd')) AS year,
        MONTH(TO_DATE(CAST(accounting_year_month AS VARCHAR(6)) || '01', 'yyyyMMdd')) AS month,
        1 AS day
    FROM 
        datalake_robin_hood_clean.tax_ratio AS tr
    JOIN 
        datalake_robin_hood_clean.tax AS t
            ON tr.id_tax = t.id
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_source AS aes
            ON tr.id_source = aes.id
    WHERE 
        tr.amount > 0
        AND t.ts_disabled IS NULL
        AND ts_blocked IS NULL
        AND LOWER(aes.source_name) IN ('porteiros', 'indica aí agents', 'indica aí')
        AND TO_DATE(CAST(accounting_year_month AS VARCHAR(6)) || '01', 'yyyyMMdd') BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    GROUP BY ALL
)
SELECT
    source_name,
    cost_type,
    id_rh_accounting_entry,
    id_external,
    id_payee,
    city_group,
    description,
    source_bill_item,
    commission_type,
    vertical,
    cost_center_code,
    company_report_origin,
    business_context,
    dt_cost,
    total_costs,
    year,
    month,
    day
FROM commission_costs
UNION ALL
SELECT
    source_name,
    cost_type,
    id_rh_accounting_entry,
    id_external,
    id_payee,
    city_group,
    description,
    source_bill_item,
    commission_type,
    vertical,
    cost_center_code,
    company_report_origin,
    business_context,
    dt_cost,
    total_costs,
    year,
    month,
    day
FROM manual_tax