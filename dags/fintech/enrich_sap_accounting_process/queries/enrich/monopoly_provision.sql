WITH 
monopoly AS (
  SELECT
    st.id AS id_finance_entity,
    ae.id,
    ae.id_sale_transaction,
    '420032' AS account_number,
    'Monopoly' AS source_name,
    'Brokerage For Sale (Platform)' AS accounting_name,
    s.id_external_offer,
    st.id_external_sync AS id_feature,
    ne.error_type,
    CASE
      WHEN st.event = 'nf-provision-reversion' THEN SUM(ae.credit) * -1
      WHEN st.event = 'nf-provision' THEN SUM(ae.credit) 
      ELSE 0 
    END AS source_amount,
    MIN(sr.dt_notary_start) AS dt_source_trigger,
    SUM(sr.total_payment_amount * sr.brokerage_fee * sr.brokerage_quintoandar_fee) AS credit
  FROM
      datalake_monopoly_clean.sale s
  LEFT JOIN datalake_monopoly_clean.sale_revision sr
      ON s.id = sr.id
      AND s.current_revision = sr.revision
  LEFT JOIN datalake_monopoly_clean.sale_transaction st
      ON st.id_sale = s.id AND st.event IN ('nf-provision', 'nf-provision-reversion')
  LEFT JOIN datalake_monopoly_clean.accounting_entry ae
      ON ae.id_sale_transaction = st.id AND ae.entry_type IN ('brokerage-quintoandar')
  LEFT JOIN datalake_monopoly_clean.nota_fiscal_emission_error ne
      ON s.id = ne.id_sale
  WHERE
    sr.dt_notary_start >= '2025-01-01'
    AND st.id_external_sync IS NOT NULL
    AND ae.credit <> 0
  GROUP BY 
    st.id, 
    ae.id, 
    ae.id_sale_transaction, 
    ae.entry_type, 
    s.id_external_offer, 
    st.id_external_sync, 
    ne.error_type, 
    st.event
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
  WHERE 1=1
    AND s.erp_solution IN ('S4')
    AND s.type IN ('LCM')
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2024-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) = 1  
),
sap_gateway_base AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.type,
    s.status AS sync_sap_job_status,
    w.status AS sap_send_status,
    w.webhook_status AS sap_processed_status,
    w.errors AS webhook_error
  FROM
    datalake_sap_gateway_clean.feature f
  LEFT JOIN
    datalake_sap_gateway_clean.sync_sap_job s
      ON f.id_feature = s.id_feature
  LEFT JOIN
    datalake_sap_gateway_clean.webhook_log w
      ON s.idoc = w.idoc
  WHERE 1=1
    AND s.erp_solution IN ('S4')
    AND s.type IN ('LCM')
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2024-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature, s.hash ORDER BY s.ts_updated) = 1  
),
sap_ledger AS (
SELECT
    l.id_finance_entity,
    l.account_number,
    sg.id_feature,
    SUM(l.debit_credit) AS debit_credit,
    MAX(DATE(l.dt_created)) AS dt_sap_created,
    MAX(DATE(l.dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger l
  INNER JOIN 
    sap_gateway_base sg ON l.hash = sg.hash
  WHERE 1=1
    AND dt_reference >= DATE('2024-01-01')
    AND account_number = '420032'
  GROUP BY 1, 2, 3
),
errors_base AS (
  SELECT
    m.id_external_offer AS id_business_entity,
    COALESCE(m.id_finance_entity, sl.id_finance_entity) AS id_finance_entity,
    CAST(NULL AS INT) AS id_finance_entity_entry,
    CAST(NULL AS STRING) AS version,
    m.source_name,
    m.account_number,
    m.accounting_name,
    DATE_FORMAT(m.dt_source_trigger, 'yyyyMM') AS accrual_year_month,
    MIN(CASE
      WHEN sl.id_finance_entity IS NOT NULL THEN 'success'
      WHEN sl.id_finance_entity IS NULL AND (m.id_feature IS NULL OR m.error_type IS NOT NULL) THEN 'source failure'
      WHEN sl.id_finance_entity IS NULL AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL) THEN 'gateway failure'
      ELSE 'unknown failure'
    END) AS accounting_process_status,
    MIN(CASE
      WHEN sl.id_finance_entity IS NULL AND m.error_type IS NOT NULL THEN m.error_type
      WHEN sl.id_finance_entity IS NULL AND sg.id_feature IS NULL THEN 'gateway not found'
      WHEN sl.id_finance_entity IS NULL AND sg.sync_sap_job_status = 'error' THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, '')
      WHEN sl.id_finance_entity IS NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
      ELSE CAST(NULL AS STRING)
    END) AS error_description,
    MIN(IF(sl.id_finance_entity IS NULL, FALSE, TRUE)) AS is_completeness,
    CAST(SUM(m.source_amount) AS DECIMAL(12,2)) AS source_amount,
    CAST(SUM(sl.debit_credit) AS DECIMAL(12,2)) AS sap_amount,
    MAX(m.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    monopoly m
  LEFT JOIN
    sap_gateway sg
      ON m.id_feature = sg.id_feature
  LEFT JOIN
    sap_ledger sl
      ON sl.id_feature = m.id_feature
      AND m.account_number = sl.account_number
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
assertions_base AS (
  SELECT
    ('MNPL-P'||'-'||COALESCE(id_finance_entity_entry, id_finance_entity)||'-'||COALESCE(account_number, '')) AS id_accounting_process,
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
    IF(dt_sap_reference BETWEEN dt_source_trigger AND DATE_ADD(dt_source_trigger, 8), TRUE, FALSE) AS is_temporality
  FROM
    errors_base
)
SELECT
  id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY id_accounting_process ORDER BY dt_sap_created) AS id_accounting_process,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  'for sale' AS business_unit,
  source_name,
  'provision' AS accounting_type,
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