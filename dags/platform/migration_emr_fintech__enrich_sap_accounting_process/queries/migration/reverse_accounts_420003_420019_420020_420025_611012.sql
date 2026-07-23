WITH sap_entity AS (
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
),

retsuko_entry AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    e.id_external AS id_external,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/rental-anticipation-fee') THEN '420019'
      WHEN e.bill_item IN ('entry.bill-item/property-damage-fine') THEN '420003'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/rental-anticipation-fee') THEN 'rental anticipation fee'
      WHEN e.bill_item IN ('entry.bill-item/property-damage-fine') THEN 'property damage fine'
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
    TRUE
    AND e.bill_item IN ('entry.bill-item/rental-anticipation-fee', 'entry.bill-item/property-damage-fine')
    AND ct.country_code = 'BR'
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')
),

retsuko_invoice AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    CAST(NULL AS INT) AS id_finance_entity_entry,
    i.id_external AS id_external,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/fine-and-interest', 'entry.bill-item/fine', 'entry.bill-item/negotiation-fine') THEN '420003'
      WHEN e.bill_item IN ('entry.bill-item/credit-card-revenue') THEN '420020'
      WHEN e.bill_item IN ('entry.bill-item/negotiation-fine-and-interest') THEN '420025'
      WHEN e.bill_item IN ('entry.bill-item/interest', 'entry.bill-item/negotiation-interest') THEN '611012'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/fine-and-interest') THEN 'fine and interest'
      WHEN e.bill_item IN ('entry.bill-item/negotiation-fine-and-interest') THEN 'negotiation fine and interest'
      WHEN e.bill_item IN ('entry.bill-item/negotiation-fine') THEN 'negotiation fine'
      WHEN e.bill_item IN ('entry.bill-item/negotiation-interest') THEN 'negotiation interest'
      WHEN e.bill_item IN ('entry.bill-item/credit-card-revenue') THEN 'credit card revenue'
      WHEN e.bill_item IN ('entry.bill-item/fine') THEN 'fine'
      WHEN e.bill_item IN ('entry.bill-item/interest') THEN 'interest'
    END AS accounting_name,
    i.accrual_year_month,
    DATE(i.ts_paid) AS dt_source_trigger,
    CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount
  FROM
    datalake_retsuko.entry  e
  INNER JOIN
    datalake_retsuko.invoice i
      ON e.id_invoice = i.id
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  LEFT JOIN
    sap_entity se
      ON i.id_external = se.id_finance_entity
  WHERE
    TRUE
    AND (
      e.bill_item IN('entry.bill-item/fine-and-interest', 'entry.bill-item/fine', 'entry.bill-item/negotiation-fine-and-interest', 'entry.bill-item/interest', 'entry.bill-item/negotiation-fine', 'entry.bill-item/negotiation-interest')
      OR (e.bill_item IN('entry.bill-item/credit-card-revenue') AND (se.version = 'v2' OR se.version IS NULL))
    )
    AND ct.country_code = 'BR'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
    HAVING
      SUM(amount) != 0
),

retsuko_final AS (
  SELECT * FROM retsuko_entry
  UNION ALL
  SELECT * FROM retsuko_invoice
),

sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.status as sync_sap_job_status
  FROM
    datalake_sap_gateway_clean.feature f
  LEFT JOIN
    datalake_sap_gateway_clean.sync_sap_job s
      ON f.id_feature = s.id_feature
  WHERE
    s.erp_solution IN ('S4')
    AND s.type = 'LCM'
    AND s.status NOT IN ('ignore', 'ignored')
),

sap_ledger AS (
SELECT 
  hash,
  id_transaction,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  accrual_year_month,
  account_number,
  DATE(dt_created) AS dt_sap_created,
  DATE(dt_reference) AS dt_sap_reference,
  debit_credit
FROM
  datalake_pas.ledger
WHERE
  dt_reference >= DATE('2025-01-01')
  AND account_number IN ('420003', '420019', '420020', '420025', '611012')
  AND source_client NOT IN ('rental-guarantee-pla')
)

SELECT
  ('RE-RTSK-RRA-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process,
  sl.id_business_entity,
  sl.id_finance_entity,
  sl.id_finance_entity_entry,
  se.version,
  'for rent' AS business_unit,
  's4' AS source_name,
  'revenue accounting' AS accounting_type,
  sl.account_number,
  r.accounting_name,
  CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
  CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  MIN(CASE
    WHEN r.id_external IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
    WHEN r.id_external IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
    WHEN r.id_external IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number'
    ELSE NULL
  END) AS error_description,
  sl.accrual_year_month AS accrual_year_month,
  r.dt_source_trigger AS dt_source_trigger,
  sl.dt_sap_reference AS dt_sap_reference,
  sl.dt_sap_created AS dt_sap_created
FROM
  sap_ledger sl
LEFT JOIN
  sap_gateway sg
    ON sl.hash = sg.hash   
LEFT JOIN
  sap_entity se
    ON se.id_sap_gateway_feature = sg.id_feature
LEFT JOIN  
  retsuko_final r
    ON COALESCE(se.id_finance_entity, REGEXP_REPLACE(sl.id_finance_entity, '[^0-9]', '')) = r.id_external AND r.account_number = sl.account_number
WHERE 
  r.id_external IS NULL
GROUP BY ALL