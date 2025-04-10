WITH payments_in_retsuko AS (
    SELECT
        c.id_external AS id_contract,
        i.id_external AS id_invoice,
        CAST(CASE 
            WHEN INSTR(i.payment_company_use_number, '|') > 0 THEN SUBSTRING_INDEX(i.payment_company_use_number, '|', -1)
            ELSE i.payment_company_use_number
        END AS STRING) AS company_use,
        i.paid_amount AS billing_source_amount,
        i.accrual_year_month,
        DATE(i.ts_paid) AS dt_billing_source,
        dd.next_brz_fintech_business_day AS dt_billing_source_trigger,
        se.id_sap_gateway_feature,
        se.id_finance_entity,
        se.version,
        se.status,
        'Seu Barriga' AS billing_source,
        se.ts_created,
        se.ts_synced
    FROM 
        datalake_retsuko.invoice AS i
    LEFT JOIN 
        datalake_retsuko_clean.contract AS c
            ON i.id_contract = c.id
    LEFT JOIN 
        dw_public.dim_date AS dd 
            ON dd.date = i.ts_paid
    LEFT JOIN 
        datalake_retsuko_clean.sap_entity AS se
            ON i.id_external = se.id_finance_entity AND se.event = 'payment-accounting-entries'
    WHERE
        i.payment_company_use_number IS NOT NULL
        AND TRIM(i.payment_company_use_number) != ''
        AND lower(i.paid_via) IN ('cnab', 'checkout-boleto', 'cyber-boleto', 'cyber-pix', 'collector-5A')
        AND i.due_amount <= 0
        AND i.payment_status != 'canceled'
        AND i.status = 'paid'
        AND i.country_code = 'BR'
        AND i.ts_paid >= current_date - 180
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY i.id_external, i.payment_company_use_number ORDER BY i.ts_created DESC) = 1  
),

francesinha AS (
    SELECT
        CAST(SUBSTRING(UPPER(our_number), 1, LENGTH(our_number) - 1) AS INTEGER) AS company_use,
        dt_credit AS dt_bank_paid,
        SUM(net_amount) AS bank_amount,
        '45268-8' AS bank_account_number
    FROM
        datalake_nexxera.cnab_charges_recupera
    WHERE
        bank_account = '04526'
        AND occurrence_code = '06'
        AND our_number IS NOT NULL
        AND TRIM(our_number) != ''
        AND dt_credit >= current_date - 180
    GROUP BY
        1,2

    UNION

    SELECT 
      CASE WHEN ext.origin_complement like '%BL%' THEN regexp_replace(
        substring(ext.origin_complement, 20, 20), 
        '^0+', 
        ''
      ) ELSE regexp_replace(ext.origin_complement, '^0+', '') END AS company_use,
        DATE(ext.date_accounting) AS dt_bank_paid,
        ext.amount_value AS bank_amount,
        '45268-8' AS bank_account_number
    FROM 
        datalake_itau_statements_clean.statement_879200452685 ext 
    WHERE 
        ext.operation in ('C') 
        AND ext.literal_code in ('9489')
        AND DATE(ext.date_accounting) >= current_date - 180
        
    
    UNION 

    SELECT
        UPPER(REPLACE(REGEXP_REPLACE(document_number, '^0000', ''), 'C!', '')) AS company_use,
        dt_credit AS dt_bank_paid,
        SUM(net_amount) AS bank_amount,
        '39221-6' AS bank_account_number
    FROM
        datalake_nexxera.cnab_charges
    WHERE
        bank_account = '03922'
        AND occurrence_code = '06'
        AND document_number IS NOT NULL
        AND TRIM(document_number) != ''
        AND dt_credit >= current_date - 180
    GROUP BY
        1,2
), 

payments_vans_checkout AS (
    SELECT 
        id_finance_entity AS id_invoice,
        paid_amount AS payment_source_amount,
        'Checkout Boleto' AS payment_source,
        DATE(ts_paid) AS dt_payment_source
    FROM 
        datalake_checkout_clean.boleto
    WHERE
        id_requester = 5

    UNION

    SELECT
        fni.id_invoice_extra AS id_invoice,
        b.paid_amount AS payment_source_amount,
        'Checkout Bolecode' AS payment_source,
        b.dt_credit AS dt_payment_source
    FROM 
        datalake_checkout_clean.bolecode AS b
    INNER JOIN 
        dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni 
            ON fni.our_number = b.our_number
    WHERE 
        b.dt_credit >= current_date - 180
    
    UNION 

    SELECT 
        id_related_document AS id_invoice,
        paid_amount AS payment_source_amount,
        'Vans Boleto' AS payment_source,
        dt_paid AS dt_payment_source
    FROM 
        datalake_vans_clean.boleto
    WHERE
        requested_by = 'seubarriga'
),

payments_in_gateway AS (
    SELECT
        id_feature,
        hash,
        stage_status,
        dt_feature_created,
        dt_sync_sap_job_created,
        dt_sap_job_synced
    FROM 
        datalake_accounting_funnel.erp_gateway_stages_status
),

payments_in_ledger AS (
    SELECT
        hash,
        id_finance_entity,
        account_number AS sap_account_number,
        account_name,
        debit_credit AS sap_amount,
        dt_reference AS dt_sap_reference,
        dt_created AS dt_sap_created
    FROM 
        datalake_accounting_funnel.ledger
    WHERE 
        account_number IN (
            '11016X',
            '11004X',
            '11010X',
            '11036X',
            '11118X',
            '11035X',
            '11036X',
            '11035X',
            '11057X',
            '11307X'
        )
),

create_compliance_columns AS (
    SELECT 
        r.id_contract AS id_business_entity,
        r.id_invoice AS id_finance_entity,
        r.company_use,
        r.version,
        r.billing_source,
        pcv.payment_source,
        f.bank_account_number,
        l.sap_account_number,
        r.accrual_year_month,
        r.billing_source_amount,
        pcv.payment_source_amount,
        f.bank_amount,
        l.sap_amount,
        IF(l.hash IS NOT NULL, TRUE, FALSE) AS is_completeness_compliance,
        IF((ABS(r.billing_source_amount) - ABS(l.sap_amount) = 0), TRUE, FALSE) AS is_correctness_compliance,
        IF((l.dt_sap_reference BETWEEN r.dt_billing_source AND DATE_ADD(r.dt_billing_source_trigger, 3)), TRUE, FALSE) AS is_temporality_compliance,
        r.dt_billing_source_trigger,
        pcv.dt_payment_source,
        f.dt_bank_paid,
        l.dt_sap_created,
        l.dt_sap_reference
    FROM
        payments_in_retsuko AS r
    LEFT JOIN 
        payments_vans_checkout AS pcv
            ON r.id_invoice = pcv.id_invoice
    LEFT JOIN 
        francesinha AS f
            ON r.company_use = CAST(f.company_use AS STRING)
    LEFT JOIN 
        payments_in_gateway AS g
            ON r.id_sap_gateway_feature = g.id_feature
    LEFT JOIN 
        payments_in_ledger AS l 
            ON g.hash = l.hash
)

SELECT
    id_business_entity,
    id_finance_entity,
    company_use,
    version,
    billing_source,
    payment_source,
    bank_account_number,
    sap_account_number,
    accrual_year_month,
    billing_source_amount,
    payment_source_amount,
    bank_amount,
    sap_amount,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    IF(is_completeness_compliance = TRUE AND is_correctness_compliance = TRUE AND is_temporality_compliance = TRUE, TRUE, FALSE) AS is_compliance,
    dt_billing_source_trigger,
    dt_payment_source,
    dt_bank_paid,
    dt_sap_created,
    dt_sap_reference
FROM 
    create_compliance_columns