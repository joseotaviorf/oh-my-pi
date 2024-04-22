WITH pre_seu_barriga AS (
    SELECT
        sk_contract AS id_contract,
        id_invoice,
        CASE
            WHEN bill_item IN ('brokerage partner select', 'brokerage partner select postponed') THEN 'select'
            WHEN bill_item IN ('brokerage adm partner', 'brokerage adm partner postponed') AND LOWER(description) LIKE '%consultor imobiliário%' THEN 'ciq'
            WHEN bill_item IN ('brokerage third party real estate', 'brokerage third party real estate postponed') THEN '3p'
            WHEN bill_item IN ('brokerage estate agent', 'brokerage estate agent postponed') THEN 'estate agent'
            WHEN bill_item IN ('brokerage quinto andar', 'brokerage quinto andar postponed') THEN 'quintoandar'
        END AS partner_type,
        accrual_year_month,
        MAX(IF(lower(bill_item) LIKE '%postponed' AND lower(description) LIKE 'crédito%', TRUE, FALSE)) AS has_postponed_brokerage,
        SUM(due_amount) AS source_due_amount
    FROM 
        datalake_accounting_funnel.invoice_all
    WHERE TRUE
        AND (
            (bill_item IN ('brokerage partner select', 'brokerage partner select postponed', 'brokerage third party real estate', 'brokerage third party real estate postponed')) OR 
            (bill_item IN ('brokerage adm partner', 'brokerage adm partner postponed') AND LOWER(description) LIKE '%consultor imobiliário%') OR 
            (bill_item IN ('brokerage estate agent', 'brokerage estate agent postponed')) OR 
            (bill_item IN ('brokerage quinto andar', 'brokerage quinto andar postponed'))
        )
        AND status != 'canceled'
        AND id_invoice > 0
        AND contract_status IN ('Ativo','Finalizado')
        AND ((ended_before_started = false) OR (status IN ('divergent payment', 'paid')))
    GROUP BY 1,2,3,4
),

seu_barriga AS (
    SELECT
        id_contract,
        id_invoice,
        partner_type,
        accrual_year_month,
        has_postponed_brokerage,
        source_due_amount,
        SUM(source_due_amount) OVER (PARTITION BY id_contract, partner_type) AS source_due_amount_accumulated
    FROM
        pre_seu_barriga
),

rh_select AS (
    SELECT
        COALESCE(ae.id_contract, regexp_extract(ae.description, '(\\d+)', 0)) AS id_contract,
        ae.accrual_year_month,
        'select' AS source_name,
        SUM(ae.due_amount) AS payment_due_amount
    FROM 
        datalake_robin_hood.accounting_entry as ae
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_source AS aes 
            ON aes.id = ae.id_source
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_balance AS eb 
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN 
        datalake_robin_hood_clean.payment_request AS pr 
            ON pr.id = eb.id_payment_request
    WHERE 
        aes.source_name IN ('Executivo For Rent')
        AND pr.status = 'paid'
        GROUP BY 1,2,3
),

rh_ciq AS (
    SELECT
        COALESCE(ae.id_contract, regexp_extract(ae.description, '(\\d+)', 0)) AS id_contract,
        ae.accrual_year_month,
        'ciq' AS source_name,
        SUM(ae.due_amount) AS payment_due_amount
    FROM 
        datalake_robin_hood.accounting_entry as ae
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_source AS aes 
            ON aes.id = ae.id_source
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_balance eb 
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN 
        datalake_robin_hood_clean.payment_request pr 
            ON pr.id = eb.id_payment_request
    WHERE
        aes.source_name IN ('CIQ Campanhas')
        AND ae.id_source = 8
        AND ae.cost_center_code IN ('C074', 'R01450', 'X01448')
        AND pr.status = 'paid'
    GROUP BY 1,2,3
),

rh_3p AS (
    SELECT
        COALESCE(ae.id_contract, regexp_extract(ae.description, '(\\d+)', 0)) AS id_contract,
        ae.accrual_year_month AS accrual_year_month,
        '3p' AS source_name,
        SUM(ae.due_amount) AS payment_due_amount
    FROM 
        datalake_robin_hood.accounting_entry as ae
    LEFT JOIN   
        datalake_robin_hood_clean.accounting_entry_source AS aes 
            ON aes.id = ae.id_source
    LEFT JOIN   
        datalake_robin_hood_clean.accounting_entry_balance eb 
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN 
        datalake_robin_hood_clean.payment_request pr 
            ON pr.id = eb.id_payment_request
    WHERE 
        aes.source_name IN ('Imobiliárias for rent')
        AND pr.status = 'paid'
    GROUP BY 1,2,3
),

rh_visitas AS (
    SELECT
        COALESCE(ae.id_contract, regexp_extract(ae.description, '(\\d+)', 0)) AS id_contract,
        ae.accrual_year_month AS accrual_year_month,
        'estate agent' AS source_name,
        SUM(ae.due_amount) AS payment_due_amount
    FROM 
        datalake_robin_hood.accounting_entry AS ae
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_source AS aes 
            ON aes.id = ae.id_source
    LEFT JOIN 
        datalake_robin_hood_clean.accounting_entry_balance eb 
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN 
        datalake_robin_hood_clean.payment_request pr 
            ON pr.id = eb.id_payment_request
    WHERE 
        aes.source_name IN ('Corretagem de aluguel')
        AND pr.status = 'paid'
    GROUP BY 1,2,3
),

pre_robin_hood AS (
    SELECT * 
    FROM 
        rh_select
    UNION ALL 
    SELECT * 
    FROM 
        rh_ciq
    UNION ALL 
    SELECT * 
    FROM 
        rh_3p
    UNION ALL 
    SELECT * 
    FROM 
        rh_visitas
),

robin_hood AS (
    SELECT 
        id_contract,
        accrual_year_month,
        source_name,
        COALESCE(payment_due_amount, 0.00) AS payment_due_amount,
        SUM(payment_due_amount) OVER (PARTITION BY id_contract, source_name) AS payment_due_amount_accumulated
    FROM
        pre_robin_hood
),

main AS (
SELECT 
    id_contract,
    partner_type,
    dt_contract_started,
    brokerage_amount
FROM 
    contract_brokerage UNPIVOT (
        brokerage_amount FOR partner_type IN (
            5A_brokerage_amount AS `quintoandar`,
            agent_brokerage_amount AS `estate agent`,
            ciq_brokerage_amount AS `ciq`,
            select_brokerage_amount AS `select`,
            3p_brokerage_amount AS `3p`)
            )
)

SELECT
    CASE 
        WHEN main.partner_type = 'quintoandar' THEN '5A-' || sb.id_contract || '-' || sb.id_invoice
        WHEN main.partner_type = 'ciq' THEN 'CIQ-' || sb.id_contract || '-' || sb.id_invoice
        WHEN main.partner_type = 'select' THEN 'SEL-' || sb.id_contract || '-' || sb.id_invoice
        WHEN main.partner_type = 'estate agent' THEN 'EA-' || sb.id_contract || '-' || sb.id_invoice 
        WHEN main.partner_type = '3p' THEN '3P-' || sb.id_contract || '-' || sb.id_invoice 
    END AS id_brokerage_transfer,
    main.id_contract,
    sb.id_invoice,
    sb.accrual_year_month,
    main.partner_type,
    COALESCE(main.brokerage_amount, 0.00) AS contract_amount,
    COALESCE(sb.source_due_amount, 0.00) AS source_due_amount,
    COALESCE(rh.payment_due_amount, 0.00) as payment_due_amount,
    COALESCE(sb.source_due_amount_accumulated, 0.00) AS source_due_amount_accumulated,
    COALESCE(rh.payment_due_amount_accumulated, 0.00) AS payment_due_amount_accumulated,
    sb.has_postponed_brokerage,
    IF(main.partner_type != 'quintoandar',
        CASE
        WHEN sb.has_postponed_brokerage IS TRUE AND COALESCE(sb.source_due_amount, 0.00) - COALESCE(rh.payment_due_amount, 0.00) BETWEEN -0.05 AND 0.05 THEN TRUE
        WHEN sb.has_postponed_brokerage IS FALSE AND COALESCE(main.brokerage_amount, 0.00) - COALESCE(sb.source_due_amount_accumulated, 0.00) BETWEEN -0.05 AND 0.05 AND COALESCE(main.brokerage_amount, 0.00) - COALESCE(rh.payment_due_amount_accumulated, 0.00) BETWEEN -0.05 AND 0.05 THEN TRUE
        ELSE FALSE
    END,
        CASE
        WHEN sb.has_postponed_brokerage IS FALSE AND COALESCE(main.brokerage_amount, 0.00) - COALESCE(sb.source_due_amount_accumulated, 0.00) BETWEEN -0.05 AND 0.05 THEN TRUE
        WHEN sb.has_postponed_brokerage IS TRUE THEN TRUE
        ELSE FALSE
    END) AS is_compliance,
    main.dt_contract_started
FROM
    main 
LEFT JOIN 
    seu_barriga sb
        ON main.id_contract = sb.id_contract 
        AND main.partner_type = sb.partner_type
LEFT JOIN 
    robin_hood rh 
        ON sb.id_contract = rh.id_contract 
        AND sb.partner_type = rh.source_name
        AND (
        (sb.accrual_year_month = rh.accrual_year_month AND sb.partner_type != '3p') OR (
            sb.accrual_year_month < rh.accrual_year_month AND sb.partner_type = '3p'
            )
        )
WHERE
    sb.accrual_year_month >= 202301