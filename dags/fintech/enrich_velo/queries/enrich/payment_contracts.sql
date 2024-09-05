WITH payments_assinaturas AS (
    SELECT
        id_propose AS id_propose, 
        id_payment AS id,
        'payment_ongoing' AS origin_table,
        CAST(due_amount AS DECIMAL(38,18)) AS value,
        status_pay.desc_lvl_1 AS status,
        gateway.desc_lvl_1 AS gateway,
        billing.desc_lvl_1 AS billing_type,
        category.desc_lvl_1 AS category,
        dt_created,
        DATE_TRUNC('month', dt_created) AS month_ref_creation,
        CAST(dt_due AS DATE) AS dt_due,
        DATE_TRUNC('month', dt_due) AS month_ref_due,
        CAST(dt_paid AS DATE) AS dt_paid
    FROM 
        datalake_velo.payment p
    LEFT JOIN 
        datalake_velo.junk status_pay
        ON status_pay.id_junk = p.id_status
    LEFT JOIN 
        datalake_velo.junk gateway
        ON gateway.id_junk = p.id_payment_gateway
    LEFT JOIN 
        datalake_velo.junk billing
        ON billing.id_junk = p.id_billing_type
    LEFT JOIN 
        datalake_velo.junk category
        ON category.id_junk = p.id_payment_category
    WHERE 
        p.id_payment > 0
),
payments_assinatura_legado AS (
    SELECT
        id_propose AS id_propose, 
        id_payment AS id,
        'payment_legacy' AS origin_table,
        CAST(due_amount AS DECIMAL(38,18)) AS value,
        status_pay.desc_lvl_1 AS status,
        gateway.desc_lvl_1 AS gateway,
        billing.desc_lvl_1 AS billing_type,
        category.desc_lvl_1 AS category,
        dt_created,
        DATE_TRUNC('month', dt_created) AS month_ref_creation,
        CAST(dt_due AS DATE) AS dt_due,
        DATE_TRUNC('month', dt_due) AS month_ref_due,
        CAST(dt_paid AS DATE) AS dt_paid
    FROM 
        datalake_velo.payment_legacy p
    LEFT JOIN 
        datalake_velo.junk status_pay
        ON status_pay.id_junk = p.id_status
    LEFT JOIN 
        datalake_velo.junk gateway
        ON gateway.id_junk = p.id_payment_gateway
    LEFT JOIN 
        datalake_velo.junk billing
        ON billing.id_junk = p.id_billing_type
    LEFT JOIN 
        datalake_velo.junk category
        ON category.id_junk = p.id_payment_category
    WHERE
        p.id_payment > 0
),
payments_assinaturas_billing_direto AS (
        WITH sap AS (
        SELECT
            id_finance_entity AS id_fatura,
            id_finance_entity_entry AS id_contract,
            credit AS mensalidade_por_contrato
        FROM 
            datalake_accounting_funnel.ledger
        WHERE 
            account_name IN ('Duplicatas a Receber VELO')
            AND debit = 0
        ),
        cobranca_billing AS (
        SELECT DISTINCT
            sap.id_contract AS id_propose,
            ADD_MONTHS(DATE(CONCAT(CAST(i.accrual_year AS VARCHAR(10)),'-',CAST(i.accrual_month AS VARCHAR(10)),'-','01')),1) AS dt_ref_boleto,
            sap.mensalidade_por_contrato,
            b.status  AS status_boleto
        FROM 
            datalake_rental_guarantee_platform_clean.billing_report i
        LEFT JOIN 
            datalake_rental_guarantee_platform_clean.bill b 
            ON b.id = i.id_bill
        LEFT JOIN 
            datalake_rental_guarantee_platform_clean.entry e 
            ON e.id_billing_report = i.id
        LEFT JOIN 
            datalake_rental_guarantee_platform_clean.company c 
            ON c.id = i.id_company
        LEFT JOIN 
            datalake_velo.broker imob
            ON imob.id_broker = c.id 
        LEFT JOIN 
            datalake_rental_guarantee_platform_clean.propose p 
            ON p.id = e.propose
        LEFT JOIN 
            sap
            ON sap.id_fatura = CAST(i.id AS VARCHAR(10))
            AND sap.id_contract = CAST(p.id AS VARCHAR(10))
        )
    SELECT
        id_propose,
        -1 AS id,
        'sap_billing_direto' AS origin_table,
        CAST(mensalidade_por_contrato AS float) AS value,
        status_boleto AS status,
        'SAP_BILLING_DIRETO' AS gateway, 
        'direct_billing' AS billing_type,
        'direct_billing' AS category,
        CAST(NULL AS DATE) AS dt_created,
        DATE_TRUNC('month', dt_ref_boleto) AS month_ref_creation,
        CAST(dt_ref_boleto AS DATE) AS dt_due,
        DATE_TRUNC('month', dt_ref_boleto) AS month_ref_due,
        CAST(NULL AS DATE) AS dt_paid
    FROM
        cobranca_billing
),
deliquency AS (
    SELECT
        id_propose,
        id,
        CASE
            WHEN id_type = 0 THEN 'deliquency' 
            WHEN id_type = 4 THEN 'deliquency_renewal' 
        END AS origin_table,
        original_value AS value,
        CASE 
            WHEN not(is_active) THEN 'CANCELLED'
            WHEN amount_paid >= original_value THEN 'PAID'
            WHEN amount_paid < original_value AND amount_paid > 0 THEN 'IN PAYMENT'
            WHEN amount_paid = 0 or amount_paid IS NULL THEN 'UNPAID' 
        END AS status,
        'DELINQUENCY' AS gateway, 
        CASE 
            WHEN id_type = 0 THEN 'SIGNATURE' 
            WHEN id_type = 4 THEN 'RENEWAL' 
        END AS billing_type,
        'deliquency' AS category,
        CAST(ts_created AS DATE) AS dt_created,
        DATE_TRUNC('month', ts_created) AS month_ref_creation,
        CAST(dt_due AS DATE) AS dt_due,
        DATE_TRUNC('month', dt_due) AS month_ref_due,
        CAST(dt_paid AS DATE) AS dt_paid
    FROM 
        datalake_rental_guarantee_platform_clean.delinquency
    WHERE 
        id_type IN (0,4) 
        AND id_propose > 0
        AND is_active
),
raw_asaas AS (
    WITH table_to_fix AS (
            SELECT
                *,
                TRIM(REGEXP_EXTRACT(LOWER(REPLACE(REPLACE(description, 'proposta', ''), ':', '')), '(\\b\\d{{5,8}}\\b)', 1)) AS id_propose_adjs
            FROM
                datalake_velo_asaas_clean.payments
            WHERE
                id_external_reference = 'None'
    ),
    table_to_fix_clean AS (
            SELECT
                *,
                CASE
                    WHEN id_propose_adjs IS NOT NULL THEN CAST(id_propose_adjs AS INT)
                    ELSE NULL
                END AS id_propose_adjs_clean
            FROM
                table_to_fix
    )
    SELECT
        id_propose_adjs_clean AS id_propose,
        id,
        'velo_raw_payments' AS origin_table,
        value, 
        status,
        'VELO_RAW_PAYMENTS' AS gateway,
        billint_type AS billing_type,
        'velo_raw_payments' AS category,
        dt_created,
        DATE_TRUNC('month', dt_created) AS month_ref_creation,
        dt_due,
        DATE_TRUNC('month', dt_due) AS month_ref_due,
        dt_payment AS dt_paid
    FROM
        table_to_fix_clean
    WHERE
        id_propose_adjs_clean IS NOT NULL
        AND id_propose_adjs_clean > 1000
        AND id_propose_adjs_clean NOT IN ('', '04/2023')

    UNION ALL

    SELECT
    TRIM(id_external_reference) AS id_propose,
        id,
        'velo_raw_payments' AS origin_table,
        value, 
        status,
        'VELO_RAW_PAYMENTS' AS gateway,
        billint_type AS billing_type,
        'velo_raw_payments' AS category,
        dt_created,
        DATE_TRUNC('month', dt_created) AS month_ref_creation,
        dt_due,
        DATE_TRUNC('month', dt_due) AS month_ref_due,
        dt_payment AS dt_paid
    FROM
        datalake_velo_asaas_clean.payments
    WHERE
        id_external_reference <> 'None'
        AND id_external_reference NOT IN ('', '04/2023')
),
payments_assinaturas_complete AS (
    SELECT 
        * 
    FROM 
        payments_assinaturas
    UNION ALL
    SELECT 
        * 
    FROM 
        payments_assinatura_legado
    UNION ALL
    SELECT 
        * 
    FROM 
        payments_assinaturas_billing_direto
    UNION ALL
    SELECT 
        * 
    FROM 
        deliquency
    UNION ALL
    SELECT 
        * 
    FROM 
        raw_asaas
),
base_status AS (
    SELECT 
        *,
        CASE status
            WHEN 'SUCCESS' THEN 'A. SUCCESS'
            WHEN 'REFUSED' THEN 'C. REFUSED'
            WHEN 'CREATED' THEN 'D. CREATED'
            WHEN 'EXPIRED' THEN 'F. EXPIRED'
            WHEN 'CHARGEBACK' THEN 'E. CHARGEBACK'
            WHEN 'PROCESSING' THEN 'B. PROCESSING'
            WHEN 'REFUNDED' THEN 'G. REFUNDED'
            WHEN 'REVERSED' THEN 'H. REVERSED'
            WHEN 'SCHEDULED_REVERSAL' THEN 'I. SCHEDULED_REVERSAL'
            WHEN 'REFUND_PROCESSING' THEN 'J. REFUND_PROCESSING'
            WHEN 'IMPROPER_BILLING' THEN 'K. IMPROPER_BILLING'
            WHEN 'ERROR' THEN 'Z. ERROR'
            WHEN NULL THEN 'z. ERROR'
            WHEN 'PAID' THEN 'A1. PAID'
            WHEN 'PAID_AFTER_DUE_DATE' THEN 'A1. PAID_AFTER_DUE_DATE'
            WHEN 'OPEN' THEN 'A4. OPEN'
            WHEN 'OVERDUE' THEN 'A5. OPEN'
            WHEN 'IN PAYMENT' THEN 'A2. IN PAYMENT'
            WHEN 'UNPAID' THEN 'B6. UNPAID'
            WHEN 'RECEIVED' THEN 'A1. RECEIVED'
            WHEN 'RECEIVED_IN_CASH' THEN 'A1. RECEIVED_IN_CASH'
            WHEN 'PENDING' THEN 'A9. PENDING'
            WHEN 'CONFIRMED' THEN 'A1. CONFIRMED'
            WHEN 'CHARGEBACK_REQUESTED' THEN 'M. CHARGEBACK_REQUESTED'
            WHEN 'WRITTEN_DOWN' THEN 'L. WRITTEN_DOWN'
            WHEN 'CANCELLED' THEN 'N. CANCELLED'
            WHEN 'REFUND_REQUESTED' THEN 'E2. REFUND_REQUESTED'
            ELSE 'z. ERROR'
        END AS status_adjs
    FROM 
        payments_assinaturas_complete
    WHERE 
        id_propose IS NOT NULL
        AND id_propose <> ''
        AND dt_due IS NOT NULL
),
filtered_payments_assinaturas_complete AS (
    SELECT
        *,
        CASE
            WHEN TRY_CAST(id_propose AS INT) IS NOT NULL THEN CAST(id_propose AS INT)
            ELSE NULL
        END AS id_propose_int
    FROM
        base_status
),
base_origin AS (
    SELECT
        id_propose,
        id,
        CASE 
            WHEN origin_table = 'payment_ongoing' and gateway in ('PIXAR', 'WALLSTREET') THEN 'B1. payment'
            WHEN origin_table = 'payment_ongoing' and gateway not in ('PIXAR', 'WALLSTREET') THEN 'B2. payment'
            WHEN origin_table = 'payment_legacy' THEN 'C. payment_legacy'
            WHEN origin_table = 'sap_billing_direto' THEN 'D. sap_billing_direto'
            WHEN origin_table = 'velo_raw_payments' THEN 'E. velo_raw_payments'
            WHEN origin_table = 'omie' THEN 'F. omie'
            WHEN origin_table = 'deliquency' THEN 'G. deliquency'
            WHEN origin_table = 'deliquency_renewal' THEN 'A. deliquency_renewal'
            ELSE origin_table
        END AS origin_table,
        value,
        status_adjs,
        status AS status,
        gateway,
        billing_type,
        category,
        dt_created,
        CAST(month_ref_creation AS DATE) AS dt_month_ref_creation,
        dt_due,
        CAST(month_ref_due AS DATE) AS dt_month_ref_due,
        dt_paid
    FROM
        filtered_payments_assinaturas_complete
    WHERE
        id_propose_int IS NOT NULL
        AND id_propose_int != -1
        AND id_propose_int != 0
),
number_of_transactions AS (
    SELECT 
        id_propose, 
        dt_month_ref_due, 
        COUNT(DISTINCT gateway) as number_of_distinct_gateways_at_ref
    FROM 
        base_origin
    GROUP BY 
        1, 2
),
base_origin_ordered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id_propose, dt_month_ref_due
            ORDER BY id_propose, origin_table, dt_month_ref_due, status_adjs
        ) AS row_num
    FROM
        base_origin
)
SELECT
    base_origin_ordered.id_propose,
    id,
    origin_table,
    value,
    status,
    COALESCE(gateway, 'UNDEFINED') AS gateway,
    billing_type,
    category,
    number_of_distinct_gateways_at_ref,
    dt_created,
    dt_month_ref_creation,
    dt_due,
    base_origin_ordered.dt_month_ref_due,
    dt_paid
FROM base_origin_ordered
LEFT JOIN number_of_transactions 
    ON  number_of_transactions.id_propose = base_origin_ordered.id_propose 
    AND number_of_transactions.dt_month_ref_due = base_origin_ordered.dt_month_ref_due
WHERE
    row_num = 1
