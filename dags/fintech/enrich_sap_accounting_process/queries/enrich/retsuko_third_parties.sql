WITH aux_business_days AS (
  SELECT
    date
  FROM
    datalake_quintoandar.aux_date
  WHERE
    is_brz_business_day = TRUE
),

retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    e.id_external AS id_sap_entity_key,
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
    e.id_external AS id_sap_entity_key,
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
    AND DATE(e.ts_created) >= '2025-01-01'
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')

UNION ALL

  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    NULL AS id_finance_entity_entry,
    i.id_external AS id_sap_entity_key,
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
    AND DATE(i.ts_paid) >= '2025-01-01'
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
    AND event IN ('new-accounting-entries', 'payment-accounting-entries')
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
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) = 1
),

sap AS (
  SELECT
    id_finance_entity,
    id_finance_entity_entry,
    hash,
    account_number,
    SUM(debit_credit) AS debit_credit,
    DATE(dt_created) AS dt_sap_created,
    DATE(dt_reference) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    TRUE
    AND account_number IN ('211413', '211415', '113406', '113411', '113412')
  GROUP BY 1, 2, 3, 4, 6, 7
),

errors_base AS (
    SELECT 
        r.id_business_entity,
        r.id_finance_entity,
        r.id_finance_entity_entry,
        se.version,
        r.source_name,
        r.account_number,
        r.accounting_name,
        r.accrual_year_month,
        MIN(CASE
        WHEN (sl_hash.hash IS NOT NULL OR sl_entry.hash IS NOT NULL) THEN 'success'
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND (se.id_finance_entity IS NULL OR se.status = 'failed' OR se.failed_reason IS NOT NULL) THEN 'source failure'
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL) THEN 'gateway failure'
        ELSE 'unknown failure'
        END) AS accounting_process_status,
        MIN(CASE
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND se.id_finance_entity IS NULL THEN 'source not found'
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND se.status = 'failed' THEN se.failed_reason
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND sg.id_feature IS NULL THEN 'gateway not found'
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND sg.sync_sap_job_status = 'error' THEN sg.webhook_error
        WHEN (sl_hash.hash IS NULL AND sl_entry.hash IS NULL) AND se.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
        ELSE NULL
        END) AS error_description,
        MIN(IF(sl_hash.hash IS NULL AND sl_entry.hash IS NULL, FALSE, TRUE)) AS is_completeness,
        CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
        CAST(SUM(COALESCE(sl_hash.debit_credit, sl_entry.debit_credit, 0)) AS DECIMAL(12,2)) AS sap_amount,
        MAX(r.dt_source_trigger) AS dt_source_trigger,
        MAX(COALESCE(sl_hash.dt_sap_created, sl_entry.dt_sap_created)) AS dt_sap_created,
        MAX(COALESCE(sl_hash.dt_sap_reference, sl_entry.dt_sap_reference)) AS dt_sap_reference
    FROM
        retsuko AS r
    LEFT JOIN
        sap_entity AS se
        ON r.id_sap_entity_key = se.id_finance_entity
    LEFT JOIN
        sap_gateway AS sg
            ON se.id_sap_gateway_feature = sg.id_feature
    LEFT JOIN
        sap AS sl_hash
            ON sl_hash.hash = sg.hash AND r.account_number = sl_hash.account_number
    LEFT JOIN
        sap AS sl_entry
            ON sl_entry.id_finance_entity_entry = r.id_finance_entity_entry AND r.account_number = sl_entry.account_number
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 12
),

assertions_base AS (
  SELECT
    'RTSK-TP'||'-'||COALESCE(id_finance_entity_entry, id_finance_entity)||'-'||COALESCE(account_number, '') AS id_accounting_process,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    account_number,
    accounting_name,
    source_amount,
    sap_amount,
    is_completeness,
    accounting_process_status,
    error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    IF((ABS(source_amount) - ABS(sap_amount)) >= 0.05 OR (ABS(source_amount) - ABS(sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_correctness,
    CASE
      WHEN dt_sap_reference IS NULL OR dt_source_trigger IS NULL THEN FALSE
      WHEN TRUNC(CAST(dt_source_trigger AS DATE), 'MM') = TRUNC(CAST(dt_sap_reference AS DATE), 'MM') THEN TRUE
      WHEN
        TRUNC(CAST(dt_sap_reference AS DATE), 'MM') = ADD_MONTHS(TRUNC(CAST(dt_source_trigger AS DATE), 'MM'), 1)
        AND (
          SELECT
            COUNT(*)
          FROM
            aux_business_days ad
          WHERE
            ad.date >= LEAST(CAST(dt_source_trigger AS DATE), CAST(dt_sap_reference AS DATE))
            AND ad.date <= GREATEST(CAST(dt_source_trigger AS DATE), CAST(dt_sap_reference AS DATE))
        ) <= 3
      THEN TRUE
      ELSE FALSE
    END AS is_temporality
  FROM 
    errors_base
)

SELECT
  id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY id_accounting_process ORDER BY dt_sap_created) AS id_accounting_process,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  'for rent' AS business_unit,
  source_name,
  'third parties' AS accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  IF(is_completeness IS TRUE AND is_correctness IS TRUE AND is_temporality IS TRUE, TRUE, FALSE) AS is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created
FROM 
  assertions_base