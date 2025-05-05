WITH rental_guarantee_pix AS (
    SELECT
        id_propose AS id_business_entity,
        IF(gateway = 'CHECKOUT_V2', id_charge, unicid) AS id_finance_entity,
        LEFT(unicid, 30) AS unicid,
        CAST(NULL AS STRING) AS id_bank_payment,
        NULL AS billing_type,
        NULL AS source_system,
        'Rental Guarantee Platform - Payment' AS billing_source,
        DATE(ts_updated) AS dt_billing,
        ROUND(SUM(value), 2) AS total_amount
    FROM 
        datalake_rental_guarantee_platform_clean.payment
    WHERE 
        status = 'SUCCESS'
        AND billing_type = 'PIX'
        AND ts_created >= CURRENT_DATE - 180
    GROUP BY 1,2,3,4,5,6,7,8

    UNION ALL 

    SELECT DISTINCT
        d.id_propose AS id_business_entity,
        ap.id_bank_payment AS id_finance_entity,
        da.id_agreement_payment AS unicid,
        ap.id_bank_payment,
        billing_type,
        source_system,
        'Rental Guarantee Platform - Delinquency' AS billing_source,
        ap.dt_paid AS dt_billing,
        ap.paid_value AS total_amount
    FROM 
        datalake_rental_guarantee_platform_clean.delinquency AS d
    LEFT JOIN 
        datalake_rental_guarantee_platform_clean.delinquency_accounting AS da 
            ON d.id = da.id_delinquency
    LEFT JOIN 
        datalake_rental_guarantee_platform_clean.agreement_payment AS ap 
            ON ap.id = da.id_agreement_payment
    WHERE 
        DATE(da.dt_paid) >= CURRENT_DATE - 180

    UNION ALL

    SELECT
        i.id_company AS id_business_entity,
        i.id AS id_finance_entity,
        CAST(NULL AS STRING) AS unicid,
        b.id AS id_bank_payment,
        NULL AS billing_type,
        NULL AS source_system,
        'Rental Guarantee Platform - Direct Billing' AS billing_source,
        DATE(ts_paid) AS dt_billing,
        due_amount AS total_amount
    FROM 
        datalake_rental_guarantee_platform_clean.billing_report i
    LEFT JOIN 
        datalake_rental_guarantee_platform_clean.bill b 
            ON b.id = i.id_bill
    WHERE 
        DATE(ts_paid) >= CURRENT_DATE - 180
        AND (
                b.status != 'WRITTEN_DOWN' AND
                i.status != 'CANCELED'
            )
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY i.id ORDER BY b.ts_created DESC) = 1
),

payments_pixar_checkout AS (
    SELECT
        id_transaction AS id_finance_entity,
        id_bank_payment,
        'Pixar' AS payment_source,
        amount,
        DATE(ts_created) AS dt_paid
    FROM 
        datalake_pixar_clean.charge 
    WHERE 
        status IN ('paid', 'refunded')
    
    UNION ALL

    SELECT 
        id_charge AS id_finance_entity,
        id_bank_payment,
        'Checkout Pix' AS payment_source,
        due_amount AS amount,
        DATE(ts_paid) AS dt_paid
    FROM
        datalake_checkout_clean.pix
    WHERE 
        status = 'PAID'

    UNION ALL

    SELECT 
        id_finance_entity,
        id AS id_bank_payment,
        'Checkout Boleto' AS payment_source,
        paid_amount AS amount,
        DATE(ts_paid) AS dt_paid
    FROM
        datalake_checkout_clean.boleto
    WHERE 
        status IN ('PAID', 'PAID_AFTER_DUE_DATE')
    
    UNION ALL

    SELECT
        i.id_external AS id_finance_entity,
        LEFT(LOWER(n.id), 30) AS id_bank_payment,
        'Trato Feito' AS payment_source,
        i.total_amount AS amount,
        DATE(p.dt_paid) AS dt_paid
    FROM
        datalake_trato_feito_clean.installment i 
    INNER JOIN
        datalake_trato_feito_clean.negotiation n 
            ON n.id = i.id_negotiation 
    INNER JOIN
        datalake_trato_feito_clean.payment p
            ON p.id_installment = i.id
),

bank AS (
    SELECT 
        origin_identifier AS our_number,
        RIGHT(origin_complement,8) AS origin_complement,
        CONCAT(origin_identifier, origin_complement) AS bank_info,
        'Itaú API' AS bank_source,
        '49458-8' AS bank_account_number,
        amount_value AS bank_amount,
        date_accounting AS dt_bank_paid
    FROM 
        datalake_itau_statements_clean.statement_879200494588
    WHERE 
        operation = 'C'
        AND literal_complete NOT LIKE 'GETNET%'
        AND origin_complement IS NOT NULL

    UNION ALL

    SELECT 
        CASE
            WHEN LENGTH(TRIM(ccrv2.document_number)) > 0 THEN TRIM(REPLACE(ccrv2.document_number, 'C!', '')) 
            ELSE ccrv2.our_number 
        END AS our_number,
        TRIM(REPLACE(document_number, 'C!', '')) AS origin_complement,
        CONCAT(our_number, document_number) AS bank_info,
        'Nexxera CNAB' AS bank_source,
        '49458-8' AS bank_account_number,
        ccrv2.net_amount AS bank_amount, 
        ccrv2.dt_credit as dt_bank_paid
    FROM 
        datalake_nexxera_clean.cnab_charges_recupera_velo_2 ccrv2 
    WHERE 
        ccrv2.occurrence_code IN ('06') 
        AND ccrv2.bank_account IN ('04945') 
),

ledger AS (
    SELECT
        id_transaction,
        id_business_entity,
        LOWER(id_finance_entity) AS id_finance_entity,
        id_finance_entity_entry,
        LOWER(id_external_payment) AS id_external_payment,
        account_number,
        account_name,
        debit_credit,
        dt_reference,
        dt_created
    FROM
        datalake_accounting_funnel.ledger
    WHERE 
        account_number = '11035X'
        AND debit_credit > 0
),

the_straw AS (
SELECT
    rgp.id_business_entity,
    rgp.id_finance_entity AS id_finance_entity,
    l.id_external_payment AS id_external_payment,
    l.id_transaction AS id_sap_transaction,
    COALESCE(CASE
        WHEN rgp.billing_source = 'Rental Guarantee Platform - Payment' THEN b.our_number
        WHEN rgp.billing_source = 'Rental Guarantee Platform - Delinquency' AND rgp.billing_type = 'BOLETO' THEN b.our_number
        WHEN rgp.billing_source = 'Rental Guarantee Platform - Direct Billing' THEN b.origin_complement
        ELSE b.origin_complement 
    END, p.id_bank_payment) AS company_use,
    rgp.billing_source,
    p.payment_source,
    billing_type,
    source_system,
    bank_info,
    b.bank_source,
    b.bank_account_number,
    l.account_number AS sap_account_number,
    CAST(rgp.total_amount AS DECIMAL(14,2)) AS billing_amount,
    CAST(p.amount AS DECIMAL(14,2)) AS payment_amount,
    CAST(b.bank_amount AS DECIMAL(14,2)) AS bank_amount,
    CAST(l.debit_credit AS DECIMAL(14,2)) AS sap_amount,
    IF(l.id_transaction IS NOT NULL, TRUE, FALSE) AS is_completeness_compliance,
    IF((COALESCE(ABS(b.bank_amount), ABS(rgp.total_amount)) - ABS(l.debit_credit) = 0), TRUE, FALSE) AS is_correctness_compliance,
    IF((l.dt_reference BETWEEN rgp.dt_billing AND DATE_ADD(rgp.dt_billing, 3)), TRUE, FALSE) AS is_temporality_compliance,
    rgp.dt_billing,
    p.dt_paid AS dt_payment_platform,
    b.dt_bank_paid,
    l.dt_created AS dt_sap_created,
    l.dt_reference AS dt_sap_reference
FROM      
    rental_guarantee_pix AS rgp
LEFT JOIN 
    payments_pixar_checkout AS p
        ON rgp.id_finance_entity = p.id_finance_entity
LEFT JOIN 
    bank AS b 
        ON CASE
                WHEN rgp.billing_source = 'Rental Guarantee Platform - Payment' THEN b.our_number = p.id_bank_payment
                WHEN rgp.billing_source = 'Rental Guarantee Platform - Delinquency' AND rgp.billing_type = 'BOLETO' THEN rgp.id_finance_entity = b.our_number
                WHEN rgp.billing_source = 'Rental Guarantee Platform - Direct Billing' THEN rgp.id_finance_entity = b.origin_complement
                ELSE rgp.id_bank_payment = b.origin_complement 
            END
LEFT JOIN 
    ledger AS l 
        ON CASE
                WHEN rgp.billing_source = 'Rental Guarantee Platform - Payment' THEN LOWER(rgp.unicid) = LOWER(l.id_external_payment)
                ELSE p.id_bank_payment = l.id_external_payment AND rgp.dt_billing = l.dt_reference
                --rgp.unicid = l.id_external_payment AND rgp.dt_billing_source_trigger = l.dt_reference
            END
)

SELECT
    id_business_entity,
    COALESCE(id_finance_entity, origin_complement) AS id_finance_entity,
    COALESCE(id_external_payment, our_number) AS id_external_payment,
    id_sap_transaction,
    company_use,
    billing_source,
    payment_source,
    COALESCE(ts.bank_source, b.bank_source) AS bank_source,
    COALESCE(ts.bank_account_number, b.bank_account_number) AS bank_account_number,
    sap_account_number,
    billing_amount,
    payment_amount,
    COALESCE(ts.bank_amount, b.bank_amount) AS bank_amount,
    sap_amount,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    IF(is_completeness_compliance = TRUE AND is_correctness_compliance = TRUE AND is_temporality_compliance = TRUE, TRUE, FALSE) AS is_compliance,
    b.dt_bank_paid,
    dt_billing,
    dt_payment_platform,
    dt_sap_created,
    dt_sap_reference
FROM 
    bank AS b
LEFT JOIN 
    the_straw AS ts
    ON b.bank_info = ts.bank_info
WHERE 
    b.dt_bank_paid >= CURRENT_DATE - 180