WITH retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN '700006'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN '700007'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner', 'entry.bill-item/ipca-adm-partner-adm-fee') THEN '700009'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN '700010'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') THEN '700011'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN 'brokerage agent'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN 'brokerage CIQ'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN 'adm fee partner'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN 'brokerage select'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') THEN 'B2B brokerage partner'
    END AS accounting_name,
    i.accrual_year_month,
    DATE(e.ts_created) AS dt_source_trigger,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN CAST(-ABS(amount) AS DECIMAL(12,2))
      ELSE CAST(amount AS DECIMAL(12,2))
    END AS source_amount
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
      datalake_retsuko.invoice_info ii
        ON ii.id_invoice = i.id_external
    LEFT JOIN
      datalake_retsuko_clean.contract ct
        ON ct.id = e.id_contract
    WHERE
        TRUE
        AND e.bill_item IN ('entry.bill-item/ipca-adm-partner-adm-fee', 'entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/adm-fee-adm-partner')
        AND ct.country_code = 'BR'
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
),

retsuko_aggregate AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent') THEN '700005'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner', 'entry.bill-item/igpm-adm-partner-adm-fee') THEN '700008'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent') THEN 'brokerage partners'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN 'B2B adm partner'
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
    datalake_retsuko.invoice_info ii
      ON ii.id_invoice = i.id_external
  LEFT JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = e.id_contract
  WHERE
    TRUE
    AND e.bill_item IN ('entry.bill-item/igpm-adm-partner-adm-fee', 'entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/adm-fee-adm-partner')
    AND ct.country_code = 'BR'
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')
),

retsuko_final AS (
  SELECT 
    * 
  FROM 
    retsuko
  UNION ALL
  SELECT 
    * 
  FROM 
    retsuko_aggregate
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
    erp_solution IN ('S4')
    AND type = 'LCM'
    AND s.status NOT IN ('ignore', 'ignored')
),

sap_ledger AS (
  SELECT
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    hash,
    id_transaction,
    created_by,
    account_number,
    debit_credit,
    DATE(dt_created) AS dt_sap_created,
    DATE(dt_reference) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2025-01-01')
    AND account_number IN ('700005', '700008', '700009', '700010', '700011') -- 700006', '700007'
    AND source_client NOT IN ('rental-guarantee-pla')
)

SELECT
  ('RE-RTSK-RRS-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process, 
  sl.id_business_entity,
  sl.id_finance_entity,
  sl.id_finance_entity_entry,
  se.version,
  'for rent' AS business_unit,
  's4' AS source_name,
  'revenue share' AS accounting_type,
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
    WHEN r.id_finance_entity_entry IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
    WHEN r.id_finance_entity_entry IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
    WHEN r.id_finance_entity_entry IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number'
    ELSE NULL
  END) AS error_description,
  r.accrual_year_month,
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
  retsuko_final r
    ON (r.id_finance_entity_entry = COALESCE(se.id_finance_entity, sl.id_finance_entity_entry) AND r.account_number = sl.account_number) 
WHERE 
  r.id_finance_entity_entry IS NULL
GROUP BY ALL