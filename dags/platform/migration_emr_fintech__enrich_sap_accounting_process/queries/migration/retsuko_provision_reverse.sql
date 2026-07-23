WITH retsuko AS (
    SELECT DISTINCT
        ct.id_external AS id_business_entity,
        i.id_external AS id_finance_entity,
        e.id_external AS id_finance_entity_entry,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN '420021'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') THEN '420022'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') THEN '420023'
            WHEN e.bill_item IN ('entry.bill-item/service-fee') THEN '420037'
        END AS account_number,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') THEN 'brokerage quinto andar'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') THEN 'brokerage installment fee'
            WHEN e.bill_item IN ('entry.bill-item/service-fee') THEN 'service fee'
        END AS accounting_name,
        i.accrual_year_month,
        DATE(e.ts_created) AS dt_source_trigger,
        CAST(amount AS DECIMAL(12,2)) AS source_amount
    FROM
        datalake_retsuko.entry  e
    INNER JOIN
        datalake_retsuko_clean.account AS af
            ON e.id_from_account = af.id
    INNER JOIN
        datalake_retsuko_clean.account AS at
            ON e.id_to_account = at.id
    LEFT JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    LEFT JOIN
        datalake_retsuko_clean.contract ct
            ON ct.id = e.id_contract
    WHERE
        e.bill_item IN (
            'entry.bill-item/adm-fee', 
            'entry.bill-item/igpm-adm-fee', 
            'entry.bill-item/ipca-adm-fee', 
            'entry.bill-item/adjustment-agreement-adm-fee', 
            'entry.bill-item/lockin', 
            'entry.bill-item/brokerage-quinto-andar', 
            'entry.bill-item/brokerage-installment-fee',
            'entry.bill-item/service-fee'
            )
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
),

    sap_entity AS (
    SELECT
        id_finance_entity,
        id_sap_gateway_feature,
        version,
        event,
        status,
        failed_status,
        failed_reason
    FROM (
        SELECT
            id_finance_entity,
            id_sap_gateway_feature,
            version,
            event,
            status,
            failed_status,
            failed_reason,
            ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) AS rn
        FROM
            datalake_retsuko_clean.sap_entity
        WHERE
            id_finance_entity IS NOT NULL
            AND event = 'new-accounting-entries'
    )
    WHERE
        rn = 1
),

sap_gateway AS (
    SELECT
        id_finance_entity,
        id_feature,
        hash,
        sync_sap_job_status,
        sap_send_status,
        sap_processed_status,
        webhook_error
    FROM (
        SELECT
            f.id_finance_entity,
            s.id_feature,
            s.hash,
            s.status AS sync_sap_job_status,
            w.status AS sap_send_status,
            w.webhook_status AS sap_processed_status,
            w.errors AS webhook_error,
            ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) AS rn
        FROM
            datalake_sap_gateway_clean.feature f
        LEFT JOIN
            datalake_sap_gateway_clean.sync_sap_job s
                ON f.id_feature = s.id_feature
        LEFT JOIN
            datalake_sap_gateway_clean.webhook_log w
                ON s.idoc = w.idoc
        WHERE
            s.erp_solution IN ('S4')
            AND s.type = 'LCM'
            AND s.status NOT IN ('ignore', 'ignored')
    )
    WHERE
        rn = 1
),

sap_ledger AS (
    SELECT
        id_business_entity,
        id_finance_entity,
        id_finance_entity_entry,
        hash,
        id_transaction,
        account_number,
        debit_credit,
        accrual_year_month,
        created_by,
        DATE(dt_created) AS dt_sap_created,
        DATE(dt_reference) AS dt_sap_reference
    FROM
        datalake_pas.ledger
    WHERE
        dt_reference >= DATE('2025-01-01')
        AND (account_number IN ('420021', '420022', '420023') 
            OR (account_number IN ('420037') AND dt_reference >= DATE('2026-08-01')))
)

SELECT
    ('RE-RTSK-P-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process,
    sl.id_business_entity,
    sl.id_finance_entity,
    sl.id_finance_entity_entry,
    se.version,
    'for rent' AS business_unit,
    'S4' AS source_name,
    'provision' AS accounting_type,
    sl.account_number,
    r.accounting_name,
    sl.accrual_year_month,
    'reverse straw failure' AS accounting_process_status,
    CASE
        WHEN r.id_finance_entity IS NULL AND se.id_sap_gateway_feature IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
        WHEN r.id_finance_entity IS NULL AND se.id_sap_gateway_feature IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
        WHEN r.id_finance_entity IS NULL AND se.id_sap_gateway_feature IS NOT NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number or postponed entry'
        ELSE NULL
    END AS error_description,
    FALSE AS is_completeness,
    FALSE AS is_correctness,
    FALSE AS is_temporality,
    FALSE AS is_compliance,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
    r.dt_source_trigger AS dt_source_trigger,
    sl.dt_sap_created AS dt_sap_created,
    sl.dt_sap_reference AS dt_sap_reference
FROM
    sap_ledger sl
LEFT JOIN
    sap_gateway sg
        ON sl.hash = sg.hash
LEFT JOIN
    sap_entity se
        ON se.id_sap_gateway_feature = sg.id_feature
LEFT JOIN
    retsuko r
        ON COALESCE(se.id_finance_entity, sl.id_finance_entity_entry)  = r.id_finance_entity_entry
        OR ((sl.id_finance_entity = r.id_finance_entity) AND (r.account_number = sl.account_number))
WHERE
    r.id_finance_entity_entry IS NULL