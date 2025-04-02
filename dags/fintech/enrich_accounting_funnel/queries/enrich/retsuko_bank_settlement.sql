WITH payments_in_retsuko AS (
    SELECT
        c.id_external AS id_contract,
        i.id_external AS id_invoice,
        i.paid_amount AS source_amount,
        i.accrual_year_month,
        DATE(i.ts_paid) AS dt_source_trigger,
        dd.next_brz_fintech_business_day,
        se.id_sap_gateway_feature,
        se.id_finance_entity,
        se.version,
        se.status,
        'seu barriga' AS source_name,
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
        i.status = 'paid'
        AND i.ts_paid >= '2024-01-01'     
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
            '11004X',
            '11010X',
            '11036X',
            '11118X'
        )
)

SELECT 
    'BK'||'-'||r.id_invoice||'-'||'1'||'-'||'5'||'-'|| '1' AS id_retsuko_bank_settlement,
    r.id_contract AS id_business_entity,
    r.id_invoice AS id_finance_entity,
    NULL AS id_finance_entity_entry,
    r.version,
    r.source_name,
    NULL AS revenue_name,
    r.accrual_year_month,
    CASE
        WHEN l.hash IS NOT NULL THEN 'SUCCESS'
        WHEN l.hash IS NULL AND g.id_feature IS NOT NULL THEN 'SG FAILURE'
        WHEN l.hash IS NULL AND g.id_feature IS NULL THEN 'SB FAILURE'
    END AS status,
    r.source_amount,
    l.sap_amount,
    l.account_number,
    IF(l.hash IS NOT NULL, TRUE, FALSE) AS is_completeness_compliance,
    IF(ABS(r.source_amount) - ABS(l.sap_amount) = 0 OR (r.source_amount = 0 AND l.sap_amount IS NULL), TRUE, FALSE) AS is_correctness_compliance,
    IF(l.dt_sap_reference BETWEEN r.dt_source_trigger AND DATE_ADD(r.dt_source_trigger, 3), TRUE, FALSE) AS is_temporality_compliance,
    r.dt_source_trigger,
    l.dt_sap_created,
    l.dt_sap_reference
FROM
    payments_in_retsuko AS r 
LEFT JOIN 
    payments_in_gateway AS g
        ON r.id_sap_gateway_feature = g.id_feature
LEFT JOIN 
    payments_in_ledger AS l 
        ON g.hash = l.hash