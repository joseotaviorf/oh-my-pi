WITH payments_in_retsuko AS (
    SELECT
        c.id_external AS id_contract,
        i.id_external AS id_invoice,
        i.payment_company_use_number AS company_use,
        i.paid_amount AS billing_source_amount,
        i.accrual_year_month,
        DATE(i.ts_paid) AS dt_billing_source,
        dd.next_brz_fintech_business_day,
        se.id_sap_gateway_feature,
        se.id_finance_entity,
        se.version,
        se.status,
        'seu barriga' AS billing_source,
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
        AND lower(i.reason) NOT IN ('negotiation-5a', 'negotiation-recupera')
        AND lower(i.paid_via) IN ('cnab', 'checkout-boleto')
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
        '45268-8' AS bank_source
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
        '45268-8' AS bank_source
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
        '39221-6' AS bank_source
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
        id_related_document AS id_invoice,
        paid_amount AS payment_source_amount,
        'Vans' AS payment_source,
        dt_paid AS dt_payment_source
    FROM 
        datalake_vans_clean.boleto
    WHERE
        requested_by = 'seubarriga'

    UNION ALL

    SELECT 
        id_finance_entity AS id_invoice,
        paid_amount AS payment_source_amount,
        'Checkout' AS payment_source,
        DATE(ts_paid) AS dt_payment_source
    FROM 
        datalake_checkout_clean.boleto
    WHERE
        id_requester = 5
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
        account_number,
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
)

SELECT 
    r.id_contract AS id_business_entity,
    r.id_invoice AS id_finance_entity,
    f.company_use,
    r.version,
    r.billing_source,
    pcv.payment_source,
    f.bank_source,
    r.accrual_year_month,
    r.billing_source_amount,
    pcv.payment_source_amount,
    f.bank_amount,
    l.sap_amount,
    l.account_number,
    IF(l.hash IS NOT NULL, TRUE, FALSE) AS is_completeness_compliance,
    r.dt_billing_source,
    pcv.dt_payment_source,
    f.dt_bank_paid,
    l.dt_sap_created,
    l.dt_sap_reference
FROM
    payments_in_retsuko AS r
LEFT JOIN 
    payments_vans_checkout AS pcv
        ON pcv.id_invoice = r.id_invoice
LEFT JOIN 
    francesinha AS f
        ON f.company_use = r.company_use
LEFT JOIN 
    payments_in_gateway AS g
        ON r.id_sap_gateway_feature = g.id_feature
LEFT JOIN 
    payments_in_ledger AS l 
        ON g.hash = l.hash