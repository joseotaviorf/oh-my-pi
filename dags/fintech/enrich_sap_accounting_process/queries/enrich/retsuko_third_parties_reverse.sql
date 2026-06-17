WITH retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    NULL AS id_external,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-installment', 'entry.bill-item/brokerage-quinto-andar') THEN '211413'
      WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment', 'entry.bill-item/pro-guarantor-5A-installment-refund') THEN '211415'
      WHEN e.bill_item IN ( 
          'entry.bill-item/condominium-5A-paid',
          'entry.bill-item/condominium-usage',
          'entry.bill-item/repair-ongoing',
          'entry.bill-item/residential-protection-5A-acquittance',
          'entry.bill-item/utilities-defaulting',
          'entry.bill-item/Iptu',
          'entry.bill-item/Iptu-defaulting',
          'entry.bill-item/iptu adjustment',
          'entry.bill-item/condominium reserves funds SA paid',
          'entry.bill-item/condominium defaulting',
          'entry.bill-item/condominium-fine',
          'entry.bill-item/condominium-defaulting',
          'entry.bill-item/evictions-lawyers',
          'entry.bill-item/condominium-reserves-funds-5A-paid',
          'entry.bill-item/evictions-costs') THEN '113406'
      WHEN e.bill_item IN ('entry.bill-item/rental-anticipation','entry.bill-item/rental-anticipation-5A-paid') THEN '113411'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-installment', 'entry.bill-item/brokerage-quinto-andar') THEN 'Brokerage to be discounted - New Model'
      WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment', 'entry.bill-item/pro-guarantor-5A-installment-refund') THEN 'Revenue to be considered - Pro Guarantor'
      WHEN e.bill_item IN ( 
          'entry.bill-item/condominium-5A-paid',
          'entry.bill-item/condominium-usage',
          'entry.bill-item/repair-ongoing',
          'entry.bill-item/residential-protection-5A-acquittance',
          'entry.bill-item/utilities-defaulting',
          'entry.bill-item/Iptu',
          'entry.bill-item/Iptu-defaulting',
          'entry.bill-item/iptu adjustment',
          'entry.bill-item/condominium reserves funds SA paid',
          'entry.bill-item/condominium defaulting',
          'entry.bill-item/condominium-fine',
          'entry.bill-item/condominium-defaulting',
          'entry.bill-item/evictions-lawyers',
          'entry.bill-item/condominium-reserves-funds-5A-paid',
          'entry.bill-item/evictions-costs') THEN 'Advance Payments - New Model'
      WHEN e.bill_item IN ('entry.bill-item/rental-anticipation','entry.bill-item/rental-anticipation-5A-paid') THEN 'Rental Antecipation'
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
    (e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') AND e.description NOT LIKE 'Taxa de corretagem - QuintoAndar%'
        ) OR
    (e.bill_item IN ( 
      'entry.bill-item/pro-guarantor-5A-installment',
      'entry.bill-item/brokerage-installment',
      'entry.bill-item/pro-guarantor-5A-installment-refund',
      'entry.bill-item/condominium-5A-paid',
      'entry.bill-item/condominium-usage',
      'entry.bill-item/repair-ongoing',
      'entry.bill-item/residential-protection-5A-acquittance',
      'entry.bill-item/utilities-defaulting',
      'entry.bill-item/Iptu',
      'entry.bill-item/Iptu-defaulting',
      'entry.bill-item/iptu adjustment',
      'entry.bill-item/condominium reserves funds SA paid',
      'entry.bill-item/condominium defaulting',
      'entry.bill-item/condominium-fine',
      'entry.bill-item/condominium-defaulting',
      'entry.bill-item/evictions-lawyers',
      'entry.bill-item/condominium-reserves-funds-5A-paid',
      'entry.bill-item/evictions-costs',
      'entry.bill-item/rental-anticipation',
      'entry.bill-item/rental-anticipation-5A-paid'))
    )
    AND DATE(e.ts_created) >= '2025-01-01'
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')

UNION ALL

  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    e.id_external AS id_external,
    'seu barriga' AS source_name,
    CASE WHEN e.bill_item IN ('entry.bill-item/debit-negotiation') THEN '113412' END AS account_number,
    CASE WHEN e.bill_item IN ('entry.bill-item/debit-negotiation') THEN 'Debit Negotiation' END AS accounting_name,
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
    (e.bill_item IN ('entry.bill-item/debit-negotiation') AND i.is_write_off = false)
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')

UNION ALL

  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    NULL AS id_finance_entity_entry,
    i.id_external AS id_external,
    'seu barriga' AS source_name,
    '113412' AS account_number,
    'Debit Negotiation' AS accounting_name,
    i.accrual_year_month,
    DATE(i.ts_paid) AS dt_source_trigger,
    CAST(i.paid_amount AS DECIMAL(12,2)) AS source_amount
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
    i.status = 'written-down' AND i.is_write_off = false
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')
),

sap_entity_ranked AS (
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
    AND event IN ('new-accounting-entries', 'payment-accounting-entries')
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
    sap_entity_ranked
  WHERE
    rn = 1
),

sap_gateway_ranked AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.status AS sync_sap_job_status,
    w.status AS sap_send_status,
    w.webhook_status AS sap_processed_status,
    w.errors AS webhook_error,
    ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY w.ts_updated) AS rn
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
  FROM
    sap_gateway_ranked
  WHERE
    rn = 1
),

sap_ledger_113412_ranked AS (
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
    debit_credit,
    ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY dt_created DESC) AS rn
  FROM
    datalake_pas.ledger
  WHERE
    TRUE
    AND account_number IN ('113412')
    AND dt_reference >= '2025-01-01'
),

sap_ledger_113412_deduped AS (
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
    dt_sap_created,
    dt_sap_reference,
    debit_credit
  FROM
    sap_ledger_113412_ranked
  WHERE
    rn = 1
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
    AND account_number IN ('211413', '211415', '113406', '113411')
    AND dt_reference >= '2025-01-01'
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

  UNION ALL

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
    dt_sap_created,
    dt_sap_reference,
    debit_credit
  FROM
    sap_ledger_113412_deduped
),

accounting_balance AS (
  SELECT
      id_finance_entity_entry,
      account_number,
      SUM(debit_credit) AS accounting_balance
  FROM sap
  GROUP BY 1, 2
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
            WHEN sl_hash.account_number = '113412' THEN COALESCE(r.accounting_name, 'Debit Negotiation')
            ELSE NULL
        END AS accounting_name,
        sl_hash.accrual_year_month,
        'reverse straw failure' AS accounting_process_status,
        CASE
            WHEN sl_hash.created_by NOT IN ('WF-BATCH','MIGRACIONES','ERP Gateway') OR sl_hash.source_client IS NULL THEN 'manual transaction'
            WHEN sl_hash.source_client <> 'seubarriga' THEN CONCAT('source-',sl_hash.source_client)
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
        (r.id_finance_entity_entry IS NULL AND sl_hash.account_number IN ('211413', '211415', '113406', '113411'))
        OR (r.id_external IS NULL AND sl_hash.account_number = '113412')
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23
)
SELECT
    base.id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY base.id_accounting_process ORDER BY base.dt_sap_created) AS id_accounting_process,
    base.id_business_entity,
    base.id_finance_entity,
    base.id_finance_entity_entry,
    base.version,
    base.business_unit,
    base.source_name,
    base.accounting_type,
    base.account_number,
    base.accounting_name,
    base.source_amount,
    base.sap_amount,
    CAST(COALESCE(ab.accounting_balance, 0) AS DECIMAL(12,2)) AS accounting_balance,
    base.is_completeness,
    base.is_correctness,
    base.is_temporality,
    base.is_compliance,
    base.accounting_process_status,
    base.error_description,
    base.accrual_year_month,
    base.dt_source_trigger,
    base.dt_sap_reference,
    base.dt_sap_created
FROM
    base
LEFT JOIN
    accounting_balance ab
        ON base.id_finance_entity_entry = ab.id_finance_entity_entry
        AND base.account_number = ab.account_number
WHERE
  (base.account_number IN ('211413', '211415', '113406', '113411') AND (base.error_description NOT IN ('source-rental-guarantee', 'manual transaction') OR base.error_description IS NULL))
  OR base.account_number = '113412'