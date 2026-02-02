WITH retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-installment', 'entry.bill-item/brokerage-quinto-andar') THEN '211413'
      WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment', 'entry.bill-item/pro-guarantor-5A-installment-refund') THEN '211415'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-installment', 'entry.bill-item/brokerage-quinto-andar') THEN 'Brokerage to be discounted - New Model'
      WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment', 'entry.bill-item/pro-guarantor-5A-installment-refund') THEN 'Revenue to be considered - Pro Guarantor'
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
    (
      (e.bill_item IN (
        'entry.bill-item/pro-guarantor-5A-installment',
        'entry.bill-item/brokerage-installment',
        'entry.bill-item/pro-guarantor-5A-installment-refund')
        ) OR 
    (e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') AND e.description NOT LIKE 'Taxa de corretagem - QuintoAndar%')
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
  FROM
    datalake_retsuko_clean.sap_entity
  WHERE
    id_finance_entity IS NOT NULL
    AND event = 'new-accounting-entries'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
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
    AND s.type = 'LCM'
    AND s.status NOT IN ('ignore', 'ignored')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY w.ts_updated) = 1
),

sap AS (
  SELECT
    id_transaction,
    id_finance_entity,
    id_finance_entity_entry,
    id_business_entity,
    hash,
    account_number,
    accrual_year_month,
    source_client,
    created_by,
    DATE(dt_created) AS dt_sap_created,
    DATE(dt_reference) AS dt_sap_reference,
    SUM(debit_credit) AS debit_credit
    
  FROM
    datalake_pas.ledger
  WHERE
    TRUE
    AND account_number IN ('211413', '211415')
    AND dt_reference >= '2025-01-01'
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
base AS (
SELECT 
        ('RE-RTSK-TP-'|| sl_hash.id_transaction || '-' || COALESCE(sl_hash.account_number, '')) AS id_accounting_process,
        sl_hash.id_transaction,
        sl_hash.id_business_entity,
        sl_hash.id_finance_entity, 
        sl_hash.id_finance_entity_entry,
        se.version,
        'for rent' AS business_unit,
        'S4' AS source_name,
        'third parties' AS accounting_type,
        sl_hash.account_number,
        CASE 
            WHEN sl_hash.account_number = '211413' THEN 'Brokerage to be discounted - New Model'
            WHEN sl_hash.account_number = '211415' THEN 'Revenue to be considered - Pro Guarantor'
        END AS accounting_name,
        sl_hash.accrual_year_month,
        'reverse straw failure' AS accounting_process_status,
        CASE
            WHEN sl_hash.source_client = 'rental-guarantee' THEN 'source-rental-guarantee'
            WHEN sl_hash.created_by NOT IN ('WF-BATCH','MIGRACIONES','ERP Gateway') OR sl_hash.source_client IS NULL THEN 'manual transaction'
            WHEN r.id_finance_entity IS NULL AND se.id_sap_gateway_feature IS NULL AND sg.id_finance_entity IS NULL THEN 'transaction missing in sap gateway'
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
        sl_hash.dt_sap_reference AS dt_sap_reference
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
            ON COALESCE(se.id_finance_entity, sl_hash.id_finance_entity_entry)  = r.id_finance_entity_entry
        OR ((sl_hash.id_finance_entity = r.id_finance_entity) AND (r.account_number = sl_hash.account_number))
    WHERE
        r.id_finance_entity_entry IS NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,19, 21, 22, 23
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
WHERE error_description NOT IN ('source-rental-guarantee', 'manual transaction') OR error_description IS NULL