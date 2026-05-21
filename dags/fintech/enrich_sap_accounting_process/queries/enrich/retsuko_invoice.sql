WITH aux_business_days AS (
  SELECT
    date
  FROM
    datalake_quintoandar.aux_date
  WHERE
    is_brz_business_day = TRUE
),

original_invoice AS (
  SELECT
    id_original_invoice_external,
    MAX(ts_due) AS ts_due_original,
    MIN (id_external) id_invoice
  FROM
    datalake_retsuko.invoice
  WHERE
    ts_nf_requested IS NOT NULL
  GROUP BY 1
),

retsuko_brokerage AS (
  SELECT 
    ct.id_external AS id_business_entity,
    ct.landlord_legal_person AS contract_type,
    i.id_external AS id_finance_entity,
    CAST(NULL AS INT) AS id_finance_entity_entry,
    COALESCE(o.id_invoice, i.id_external) AS id_entity,
    o.id_invoice AS id_original_invoice,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar' THEN '420001'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'juridical' THEN '420002'
      WHEN e.bill_item = 'entry.bill-item/brokerage-installment-fee' THEN '420004'
      WHEN e.bill_item = 'entry.bill-item/pro-guarantor-5A-installment' THEN '420010'
    END AS account_number,
    CASE
      WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar' THEN 'brokerage quinto andar'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'juridical' THEN 'adm fee PJ'
      WHEN e.bill_item = 'entry.bill-item/brokerage-installment-fee' THEN 'brokerage installment fee'
      WHEN e.bill_item = 'entry.bill-item/pro-guarantor-5A-installment' THEN 'pro guarantor 5A installment'
    END AS accounting_name,
    i.accrual_year_month,
    MAX(CASE
          WHEN e.bill_item = 'entry.bill-item/pro-guarantor-5A-installment' THEN last_day(e.ts_created)
          WHEN o.id_invoice IS NOT NULL THEN DATE(o.ts_due_original)
          ELSE DATE(i.ts_due)
        END) AS dt_source_trigger,
    CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount,
    MAX(e.accounting_version) AS accounting_version
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko.invoice i
      ON e.id_invoice = i.id
  LEFT JOIN
    original_invoice o
      ON i.id_original_invoice_external = o.id_original_invoice_external
  INNER JOIN
    datalake_retsuko.invoice_info ii
      ON ii.id_invoice = i.id_external
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  WHERE
    DATE(i.ts_created) >= '2024-01-01'
    AND ct.country_code = 'BR'
    AND ii.invoice_frequency != 'extra'
    AND i.status != 'canceled'
    AND (is_write_off = FALSE OR is_write_off IS NULL)
    AND description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND (
      e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment')
      OR (
          (ii.invoice_user = 'landlord')
          AND (NOT(i.ts_due > current_date AND i.accrual_year_month < 202405))
          AND e.bill_item IN (
            'entry.bill-item/brokerage-quinto-andar', 
            'entry.bill-item/adm-fee', 
            'entry.bill-item/igpm-adm-fee', 
            'entry.bill-item/ipca-adm-fee', 
            'entry.bill-item/adjustment-agreement-adm-fee', 
            'entry.bill-item/lockin', 
            'entry.bill-item/brokerage-installment-fee')
        )
    )
    AND NOT(ct.landlord_legal_person = 'physical' AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'))
    
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  HAVING
      SUM(amount) != 0
),
retsuko_adm_service_fee AS (
  SELECT 
      ct.id_external AS id_business_entity,
      ct.landlord_legal_person AS contract_type,
      i.id_external AS id_finance_entity,
      CAST(NULL AS INT) AS id_finance_entity_entry,
      COALESCE(o.id_invoice, i.id_external) AS id_entity,
      o.id_invoice AS id_original_invoice,
      'seu barriga' AS source_name,
      CASE
        WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'physical' THEN '420002'
        WHEN e.bill_item = 'entry.bill-item/service-fee' THEN '420005'
      END AS account_number,
      CASE
        WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'physical' THEN 'adm fee PF'
        WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
      END AS accounting_name,
      i.accrual_year_month,
      MAX(CASE
        WHEN o.id_invoice IS NOT NULL THEN DATE(o.ts_due_original)
        ELSE DATE(i.ts_due)
      END) AS dt_source_trigger,
      CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount,
      MAX(e.accounting_version) AS accounting_version
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko_clean.account AS af
      ON e.id_from_account = af.id
  INNER JOIN
    datalake_retsuko_clean.account AS at
      ON e.id_to_account = at.id
  INNER JOIN
    datalake_retsuko.invoice i
      ON e.id_invoice = i.id
  LEFT JOIN
    original_invoice o
      ON i.id_original_invoice_external = o.id_original_invoice_external
  INNER JOIN
    datalake_retsuko.invoice_info ii
      ON ii.id_invoice = i.id_external
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  WHERE
    DATE(e.ts_created) >= '2026-07-01'
    AND IF(o.id_invoice IS NOT NULL,DATE(o.ts_due_original),DATE(i.ts_due)) >= '2026-07-01'
    AND ct.country_code = 'BR'
    AND af.type IN ('contract', 'tenant', 'landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    AND i.status != 'canceled'
    AND description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND  e.bill_item IN ('entry.bill-item/service-fee')
         OR (ct.landlord_legal_person = 'physical' 
            AND e.bill_item IN (
              'entry.bill-item/adm-fee', 
              'entry.bill-item/igpm-adm-fee', 
              'entry.bill-item/ipca-adm-fee', 
              'entry.bill-item/adjustment-agreement-adm-fee', 
              'entry.bill-item/lockin')
            )
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  HAVING
      SUM(amount) != 0
),

retsuko AS (
  SELECT * FROM retsuko_brokerage
  -- UNION ALL
  -- SELECT * FROM retsuko_adm_service_fee
),

sap_entity AS (
  SELECT
    id_finance_entity,
    id_sap_gateway_feature,
    event,
    status,
    failed_status,
    failed_reason
  FROM
    datalake_retsuko_clean.sap_entity
  WHERE
    id_finance_entity IS NOT NULL
    AND event IN ('tenant-invoices-paid', 'nota-fiscal-items', 'new-accounting-entries')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
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
    AND s.type IN ('NF', 'PN')
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2024-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) = 1
),

sap_ledger AS (
  SELECT
    id_finance_entity,
    account_number,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2024-01-01')
    AND account_number IN ('420001', '420002', '420004', '420005', '420010')
  GROUP BY 1, 2
),

errors_base AS (
  SELECT
    r.id_business_entity,
    r.id_finance_entity,
    r.id_finance_entity_entry,
    MAX(r.accounting_version) AS version,
    r.source_name,
    r.account_number,
    r.accounting_name,
    r.accrual_year_month,
    MIN(CASE
      WHEN sl.id_finance_entity IS NOT NULL THEN 'success'
      WHEN sl.id_finance_entity IS NULL AND (se.id_finance_entity IS NULL OR se.status = 'failed' OR se.failed_reason IS NOT NULL) THEN 'source failure'
      WHEN sl.id_finance_entity IS NULL AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL) THEN 'gateway failure'
      ELSE 'unknown failure'
    END) AS accounting_process_status,
    MIN(CASE
      WHEN sl.id_finance_entity IS NULL AND se.id_finance_entity IS NULL THEN 'source not found'
      WHEN sl.id_finance_entity IS NULL AND se.status = 'failed' THEN se.failed_reason
      WHEN sl.id_finance_entity IS NULL AND sg.id_feature IS NULL THEN 'gateway not found'
      WHEN sl.id_finance_entity IS NULL AND sg.sync_sap_job_status = 'error' THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, '')
      WHEN sl.id_finance_entity IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
      ELSE NULL
    END) AS error_description,
    MIN(IF(sl.id_finance_entity IS NULL, FALSE, TRUE)) AS is_completeness,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
    MAX(r.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    retsuko r
  LEFT JOIN
    sap_entity se
    ON se.id_finance_entity = r.id_entity
  LEFT JOIN
    sap_gateway sg
      ON se.id_sap_gateway_feature = sg.id_feature
  LEFT JOIN
    sap_ledger sl
      ON r.account_number = sl.account_number
      AND sl.id_finance_entity = r.id_entity
    GROUP BY 1, 2, 3, 5, 6, 7, 8, 12, 13
),


assertions_base AS (
  SELECT
    ('RTSK-I'||'-'||COALESCE(id_finance_entity_entry, id_finance_entity)||'-'||COALESCE(account_number, '')) AS id_accounting_process,
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
  'invoice' AS accounting_type,
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