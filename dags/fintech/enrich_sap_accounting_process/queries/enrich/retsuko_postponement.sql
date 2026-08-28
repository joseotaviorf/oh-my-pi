WITH aux_business_days AS (
  SELECT
    date
  FROM
    datalake_quintoandar.aux_date
  WHERE
    is_brz_business_day = TRUE
),

sap_entity_ranked AS (
  SELECT
    id_finance_entity,
    id_sap_gateway_feature,
    version,
    status,
    failed_status,
    failed_reason,
    ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY id_sap_gateway_feature DESC, ts_updated DESC) AS rn
  FROM
    datalake_retsuko_clean.sap_entity
  WHERE
    id_finance_entity IS NOT NULL
    AND event = 'new-accounting-entries'
),

sap_entity AS (
  SELECT
    id_finance_entity,
    id_sap_gateway_feature,
    version,
    status,
    failed_status,
    failed_reason
  FROM
    sap_entity_ranked
  WHERE
    rn = 1
),

retsuko_entry AS (
  SELECT DISTINCT
    CAST(ct.id_external AS STRING) AS id_business_entity,
    CAST(i.id_external AS STRING) AS id_finance_entity,
    CAST(e.id_external AS STRING) AS id_finance_entity_entry,
    CAST(e.id_external AS STRING) AS id_external,
    'seu barriga' AS source_name,
    '211407' AS account_number,
    'postponed invoice PP' AS accounting_name,
    i.accrual_year_month,
    DATE(e.ts_created) AS dt_source_trigger,
    CAST(e.amount AS DECIMAL(12,2)) AS source_amount
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko.invoice i
      ON CAST(e.id_invoice AS STRING) = CAST(i.id AS STRING)
  INNER JOIN
    datalake_retsuko_clean.account ia
      ON ia.id = i.id_account
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  WHERE
    e.bill_item = 'entry.bill-item/postponement'
    -- proxy do cliente PP: a fatura pertence a uma conta de proprietario
    AND ia.type = 'landlord'
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= '2025-01-01'
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

sap_ledger AS (
  SELECT
    id_finance_entity,
    id_finance_entity_entry,
    hash,
    account_number,
    SUM(debit_credit) OVER (PARTITION BY COALESCE(id_finance_entity_entry, id_finance_entity), account_number) AS debit_credit,
    MAX(DATE(dt_created)) OVER (PARTITION BY COALESCE(id_finance_entity_entry, id_finance_entity), account_number) AS dt_sap_created,
    MAX(DATE(dt_reference)) OVER (PARTITION BY COALESCE(id_finance_entity_entry, id_finance_entity), account_number) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    account_number = '211407'
),

-- conta irma da postergacao: usada apenas para separar divergencia de classificacao de falha real
sap_ledger_iq AS (
  SELECT DISTINCT
    CAST(id_finance_entity_entry AS STRING) AS id_finance_entity_entry
  FROM
    datalake_pas.ledger
  WHERE
    account_number = '113403'
    AND id_finance_entity_entry IS NOT NULL
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
      WHEN sl.hash IS NOT NULL THEN 'success'
      WHEN sl.hash IS NULL AND iq.id_finance_entity_entry IS NOT NULL THEN 'account divergence'
      WHEN sl.hash IS NULL AND (se.id_finance_entity IS NULL OR se.status = 'failed' OR se.failed_reason IS NOT NULL) THEN 'source failure'
      WHEN sl.hash IS NULL AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL) THEN 'gateway failure'
      ELSE 'unknown failure'
    END) AS accounting_process_status,
    MIN(CASE
      WHEN sl.hash IS NOT NULL THEN NULL
      WHEN iq.id_finance_entity_entry IS NOT NULL THEN 'accounted in 113403 - IQ postponed invoice'
      WHEN se.id_finance_entity IS NULL THEN 'source not found'
      WHEN se.status = 'failed' THEN se.failed_reason
      WHEN sg.id_feature IS NULL THEN 'gateway not found'
      WHEN sg.sync_sap_job_status = 'error' THEN sg.webhook_error
      WHEN se.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
      ELSE NULL
    END) AS error_description,
    MIN(IF(sl.hash IS NULL, FALSE, TRUE)) AS is_completeness,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(SUM(sl.debit_credit) AS DECIMAL(12,2)) AS sap_amount,
    MAX(r.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    retsuko_entry r
  LEFT JOIN
    sap_entity se
      ON r.id_external = CAST(se.id_finance_entity AS STRING)
  LEFT JOIN
    sap_gateway sg
      ON se.id_sap_gateway_feature = sg.id_feature
  LEFT JOIN
    sap_ledger sl
      ON sl.hash = sg.hash
      AND r.account_number = sl.account_number
      AND (
        r.id_finance_entity_entry IS NULL
        OR CAST(sl.id_finance_entity_entry AS STRING) = CAST(r.id_finance_entity_entry AS STRING)
      )
  LEFT JOIN
    sap_ledger_iq iq
      ON iq.id_finance_entity_entry = r.id_finance_entity_entry
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 12
),

assertions_base AS (
  SELECT
    ('RTSK-PSTP'||'-'||COALESCE(id_finance_entity_entry, id_finance_entity)||'-'||COALESCE(account_number, '')) AS id_accounting_process,
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
  'postponement' AS accounting_type,
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
  dt_sap_created,
  CAST(NULL AS DATE) AS dt_filter_end
FROM
  assertions_base
