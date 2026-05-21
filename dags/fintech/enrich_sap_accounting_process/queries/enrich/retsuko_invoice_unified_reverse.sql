WITH
retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    ct.landlord_legal_person AS contract_type,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item = 'entry.bill-item/service-fee' THEN '420005'
      ELSE 'ERROR'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee PF'
      WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
    END AS accounting_name,
    CASE
      WHEN e.bill_item != 'entry.bill-item/service-fee' THEN e.accrual_year_month
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine') THEN e.accrual_year_month
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine-delayed') THEN e.accrual_year_month
      WHEN ct.is_rental_paid_in_advance = false THEN e.accrual_year_month
      ELSE CAST(DATE_FORMAT(TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM') + interval '1' month, 'yyyyMM') AS INT)
    END AS accrual_year_month,
    CASE
      WHEN e.bill_item != 'entry.bill-item/service-fee' 
           OR (ct.is_rental_paid_in_advance = true AND e.producer IN ('onboarding-routine','onboarding-routine-delayed'))
           OR ct.is_rental_paid_in_advance = false 
      THEN DATE_FORMAT(LAST_DAY(TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM')), 
          'yyyy-MM-dd')
      ELSE DATE_FORMAT(LAST_DAY(TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM') + interval '1' month), 'yyyy-MM-dd')
    END AS dt_source_trigger,
    CAST(e.amount AS DECIMAL(12,2)) AS source_amount
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
    e.description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND e.bill_item IN ('entry.bill-item/service-fee')
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= DATE ('2025-01-01')
    AND af.type IN ('contract', 'tenant', 'landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    AND i.status != 'canceled'
    AND NOT(ct.landlord_legal_person = 'juridical' AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'))
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
    AND event IN ('tenant-invoices-paid', 'nota-fiscal-items', 'new-accounting-entries')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

sap_gateway AS (
   SELECT
    i.id_feature,
    i.id_finance_entity,
    i.amount,
    CAST(ci.doc_entry AS INT) AS doc_entry,
    s.status as sync_sap_job_status
FROM
    datalake_sap_gateway_clean.invoice i
LEFT JOIN
  datalake_sap_gateway_clean.consolidated_invoice ci
    ON ci.id = i.id_consolidated
INNER JOIN
  datalake_sap_gateway_clean.sync_sap_job s
    ON i.id_feature = s.id_feature
WHERE
    i.account_code in ('SRPN000001','SRPN000006')
    AND s.type IN ('NF', 'PN')
    AND s.status IN ('waiting-unified-invoice', 'done')
    AND s.erp_solution IN ('S4')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.id_finance_entity, i.id_feature ORDER BY s.ts_updated) = 1
),

sap_ledger AS (
  SELECT
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    id_transaction,
    CAST(id_external_payment AS INT) AS id_external_payment,
    account_number,
    accrual_year_month,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_accounting_funnel.ledger
  WHERE
    dt_reference >= DATE('2025-01-01') AND dt_reference < DATE('2026-07-01')
    AND account_number IN ('420005')
    AND id_finance_entity IN ('SFNFUnica', 'AdmNFUnica')
  GROUP BY 1, 2, 3, 4, 5, 6, 7
)

SELECT
    ('FR-UI-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process,
    sl.id_business_entity,
    sl.id_finance_entity,
    sl.id_finance_entity_entry,
    se.version,
    'for rent' AS business_unit,
    'S4' AS source_name,
    'unified invoice' AS accounting_type,
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
      ON sl.id_external_payment  = sg.doc_entry
 LEFT JOIN
    sap_entity se
      ON se.id_sap_gateway_feature = sg.id_feature
 LEFT JOIN
    retsuko r
      ON COALESCE(se.id_finance_entity, sl.id_finance_entity_entry) = r.id_finance_entity_entry
      OR ((sl.id_finance_entity = r.id_finance_entity) AND (r.account_number = sl.account_number))
 WHERE 1=1
 AND r.id_finance_entity_entry IS NULL