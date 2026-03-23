WITH retsuko AS (
    SELECT DISTINCT
        ct.id_external AS id_business_entity,
        i.id_external AS id_finance_entity,
        e.id_external AS id_finance_entity_entry,
        'seu barriga' AS source_name,
        '700004' AS account_number,
        'Between contracts' AS accounting_name,
        e.bill_item,
        i.accrual_year_month,
        DATE(e.ts_created) AS dt_source_trigger,
        e.ts_created,
        e.amount AS source_amount,
        e.accounting_version AS accounting_version
    FROM
        datalake_retsuko.entry e
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
        datalake_retsuko.invoice_info ii
            ON ii.id_invoice = i.id_external
    INNER JOIN
        datalake_retsuko_clean.contract ct
            ON ct.id = e.id_contract
    WHERE 1=1
        AND e.bill_item IN (
            'entry.bill-item/adjustment-agreement-rental',
            'entry.bill-item/between-contracts',
            'entry.bill-item/condominium-reserves-funds',
            'entry.bill-item/condominium-usage',
            'entry.bill-item/condominium',
            'entry.bill-item/early-termination-fee',
            'entry.bill-item/igpm-rental',
            'entry.bill-item/improvement-work',
            'entry.bill-item/ipca-rental',
            'entry.bill-item/iptu-adjustment',
            'entry.bill-item/iptu',
            'entry.bill-item/light-water-or-gas',
            'entry.bill-item/others',
            'entry.bill-item/rental',
            'entry.bill-item/repair-work',
            'entry.bill-item/residential-protection-5A-fund-transfer'

        )
        AND af.type IN ('contract', 'tenant', 'landlord')
        AND at.type IN ('contract', 'tenant', 'landlord')
        AND e.amount != 0
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
    FROM
        datalake_retsuko_clean.sap_entity
    WHERE
        id_finance_entity IS NOT NULL
        AND event IN (
        'new-accounting-entries'
      )
),

sap_gateway AS (
    SELECT
        f.id_finance_entity,
        s.id_feature,
        s.hash,
        s.type,
        s.status as sync_sap_job_status,
        w.status as sap_send_status,
        w.webhook_status as sap_processed_status,
        w.errors AS webhook_error
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
        AND s.type IN ('LCM')
        AND s.status NOT IN ('ignore', 'ignored')
        AND DATE(f.ts_created) >= DATE('2025-01-01')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature, s.hash ORDER BY w.ts_updated DESC) = 1
),

sap AS (
    SELECT 
        id_business_entity,
        id_finance_entity,
        id_finance_entity_entry,
        hash,
        account_number,
        accrual_year_month,
        source_client,
        DATE(dt_created) AS dt_sap_created,
        DATE(dt_reference) AS dt_sap_reference,
        debit_credit AS debit_credit
    FROM 
        datalake_accounting_funnel.ledger 
    WHERE
        dt_reference >= '2025-01-01'
        AND account_number IN (700004)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, id_finance_entity_entry ORDER BY dt_created DESC) = 1
)
,
base AS (
    SELECT 
        ('RE-RTSK-T-' || COALESCE(sl_hash.id_finance_entity,'') || '-' || COALESCE(sl_hash.account_number, '')) AS id_accounting_process,
        sl_hash.id_business_entity,
        sl_hash.id_finance_entity, 
        sl_hash.id_finance_entity_entry,
        se.version,
        'for rent' AS business_unit,
        'S4' AS source_name,
        'transactional' AS accounting_type,
        sl_hash.account_number,
        r.accounting_name,
        sl_hash.accrual_year_month,
        'reverse straw failure' AS accounting_process_status,
        CASE
            WHEN sl_hash.source_client <> 'seubarriga' THEN CONCAT('source','-',sl_hash.source_client)
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
        CAST(SUM(COALESCE(sl_hash.debit_credit, 0)) AS DECIMAL(12,2)) AS sap_amount,
        r.dt_source_trigger AS dt_source_trigger,
        sl_hash.dt_sap_created AS dt_sap_created,
        sl_hash.dt_sap_reference AS dt_sap_reference,
        r.id_finance_entity_entry as id_finance_entity_entry_r
    FROM
        sap AS sl_hash
    LEFT JOIN
        sap_gateway AS sg
            ON sl_hash.hash = sg.hash
    LEFT JOIN
        sap_entity AS se
            ON se.id_sap_gateway_feature = sg.id_feature
    LEFT JOIN
        retsuko AS r
        ON (
            (COALESCE(sl_hash.id_finance_entity_entry,se.id_finance_entity)  = r.id_finance_entity_entry AND (r.account_number = sl_hash.account_number))
        OR ((sl_hash.id_finance_entity = r.id_finance_entity) AND (r.account_number = sl_hash.account_number))
            )
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23
)
SELECT
    id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY id_accounting_process ORDER BY dt_sap_created) AS id_accounting_process,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    business_unit,
    source_name,
    accounting_type,
    account_number,
    accounting_name,
    source_amount,
    sap_amount,
    is_completeness,
    is_correctness,
    is_temporality,
    is_compliance,
    accounting_process_status,
    error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created
FROM base
WHERE id_finance_entity_entry_r IS NULL
