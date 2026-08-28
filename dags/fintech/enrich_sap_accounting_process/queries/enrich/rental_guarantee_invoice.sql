WITH aux_business_days AS (
  SELECT
    date
  FROM
    datalake_quintoandar.aux_date
  WHERE
    is_brz_business_day = TRUE
),

-- One row per dispatch sent by rental-guarantee to the sap-gateway. Only the three
-- revenue recognition triggers reach account 420010; payment, cancellation, refund and
-- renewal triggers post on other accounts and are out of scope here.
rental_guarantee AS (
  SELECT
    id AS id_sap_dispatch,
    id_business_entity,
    id_finance_entity,
    id_feature,
    `trigger`,
    sap_status,
    'rental guarantee' AS source_name,
    '420010' AS account_number,
    'rental guarantee' AS accounting_name,
    reference_year_month AS accrual_year_month,
    DATE(dt_event_date) AS dt_source_trigger,
    CAST(amount AS DECIMAL(12,2)) AS source_amount
  FROM
    datalake_rental_guarantee_clean.sap
  WHERE
    `trigger` IN (
      'PIX_REVENUE_RECOGNITION',
      'CREDIT_CARD_REVENUE_RECOGNITION',
      'STANDALONE_REVENUE_RECOGNITION')
    AND DATE(dt_event_date) >= DATE('2025-01-01')
),

-- The nota fiscal job is the only leg that carries the hash used by the SAP ledger.
-- Its sibling PN job is always hashless, so filtering on type = 'NF' keeps one row per feature.
-- sync_sap_job has no column identifying the originating system, so the join to feature is
-- what scopes the gateway leg to rental-guarantee and keeps other producers of the same
-- account out of this straw. feature is unique by id_feature, so the join cannot fan out.
sap_gateway AS (
  SELECT
    id_feature,
    hash,
    type,
    sync_sap_job_status,
    sap_send_status,
    sap_processed_status,
    webhook_error
  FROM (
    SELECT
      s.id_feature,
      s.hash,
      s.type,
      s.status AS sync_sap_job_status,
      w.status AS sap_send_status,
      w.webhook_status AS sap_processed_status,
      w.errors AS webhook_error,
      ROW_NUMBER() OVER (PARTITION BY s.id_feature ORDER BY s.ts_updated DESC) AS rn
    FROM
      datalake_sap_gateway_clean.sync_sap_job s
    JOIN
      datalake_sap_gateway_clean.feature f
        ON f.id_feature = s.id_feature
        AND f.source = 'rental-guarantee'
    LEFT JOIN
      datalake_sap_gateway_clean.webhook_log w
        ON s.idoc = w.idoc
    WHERE
      s.erp_solution IN ('S4')
      AND s.type = 'NF'
      AND s.status NOT IN ('ignore', 'ignored')
      AND DATE(s.ts_created) >= DATE('2025-01-01')
  )
  WHERE
    rn = 1
),

-- Account 420010 is fed by two independent sources. Seu Barriga posts through the
-- invoice-*-pro-guarantor-5A-installment rules and is reconciled by retsuko_invoice;
-- rental-guarantee posts through pro-guarantor-nf and standalone-nf. Splitting by
-- accounting_rule is what keeps the two straws from overlapping, since source_client
-- is only populated until 2024-10 and id_finance_entity_entry carries the literal
-- 'rental-guarantee' instead of an entry id on this route.
sap_ledger AS (
  SELECT
    hash,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2025-01-01')
    AND account_number = '420010'
    AND accounting_rule IN ('pro-guarantor-nf', 'standalone-nf')
    AND hash IS NOT NULL
  GROUP BY 1
),

errors_base AS (
  SELECT
    r.id_sap_dispatch,
    r.id_business_entity,
    r.id_finance_entity,
    LOWER(r.`trigger`) AS version,
    r.source_name,
    r.account_number,
    r.accounting_name,
    r.accrual_year_month,
    CASE
      WHEN sl.hash IS NOT NULL THEN 'success'
      WHEN r.id_feature IS NULL THEN 'source failure'
      WHEN sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL THEN 'gateway failure'
      ELSE 'unknown failure'
    END AS accounting_process_status,
    CASE
      WHEN sl.hash IS NOT NULL THEN CAST(NULL AS STRING)
      WHEN r.id_feature IS NULL THEN 'source not dispatched - ' || COALESCE(r.sap_status, 'unknown')
      WHEN sg.id_feature IS NULL THEN 'gateway not found'
      WHEN sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, sg.sync_sap_job_status, '')
      ELSE 'sap not found'
    END AS error_description,
    IF(sl.hash IS NULL, FALSE, TRUE) AS is_completeness,
    r.source_amount,
    CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
    r.dt_source_trigger,
    sl.dt_sap_created,
    sl.dt_sap_reference
  FROM
    rental_guarantee r
  LEFT JOIN
    sap_gateway sg
      ON CAST(sg.id_feature AS STRING) = CAST(r.id_feature AS STRING)
  LEFT JOIN
    sap_ledger sl
      ON sl.hash = sg.hash
),

assertions_base AS (
  SELECT
    ('RGRT-I'||'-'||id_sap_dispatch||'-'||COALESCE(account_number, '')) AS id_accounting_process,
    id_business_entity,
    id_finance_entity,
    CAST(id_sap_dispatch AS STRING) AS id_finance_entity_entry,
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
  dt_sap_created,
  CAST(NULL AS DATE) AS dt_filter_end
FROM
  assertions_base
