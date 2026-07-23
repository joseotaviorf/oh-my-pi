WITH deduplicate_creditor_pending AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
  FROM datalake_recupera_clean.creditor_pending
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY dt_table_insertion DESC, ts_load DESC) = 1
),
deduplicate_complementary_records AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
  FROM datalake_recupera_clean.complementary_records
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY ts_last_debt_update DESC) = 1
),
deduplicate_complementary_records_written_down AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
  FROM datalake_recupera_clean.complementary_records_written_down
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY ts_last_debt_update DESC) = 1
),
recupera_debts AS (
  SELECT
    CONCAT(COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract),
      COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice)
    ) AS id_debt,
    COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice) AS id_invoice,
    COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract,
    CONCAT(
      COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract),
      CAST(COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) AS BIGINT)
    ) AS id_negotiation,
    "Recupera" AS source,
    3 AS priority
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
      ON cp.id_contract = cr.id_contract
      AND cp.id_invoice  = cr.id_invoice
      AND cp.id_negotiation = cr.id_negotiation
  FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
      ON cp.id_contract = crwd.id_contract
      AND cp.id_invoice  = crwd.id_invoice
      AND cp.id_negotiation = crwd.id_negotiation
  WHERE COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) IS NOT NULL
),
trato_feito_debts AS (
  SELECT
    CONCAT(n.id_contract, d.id_external) AS id_debt,
    d.id_external AS id_invoice,
    CONCAT(n.id_contract, IFNULL(CAST(n.id_negotiation_external AS BIGINT),n.id_negotiation_external)) AS id_negotiation,
    n.id_contract,
    "Trato Feito" AS source,
    1 AS priority
  FROM datalake_trato_feito_clean.debt AS d
  LEFT JOIN datalake_debt_recovery.negotiation AS n
    ON d.id_negotiation = n.id_negotiation
  WHERE
    d.id_negotiation IS NOT NULL
    AND n.debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY  n.id_contract, d.id_external, d.id_negotiation ORDER BY  d.ts_created DESC) = 1
),
cyber_debts AS (
  SELECT
    CONCAT(id_contract, id_invoice) AS id_debt,
    id_contract,
    CONCAT(id_contract, CAST(id_negotiation AS BIGINT)) AS id_negotiation,
    id_invoice,
    "Cyber" AS source,
    2 AS priority
  FROM datalake_cyber.debt_negotiation_mapping
),
union_sources AS (
SELECT
  COALESCE(t.id_debt, c.id_debt, r.id_debt) AS sk_debt,
  CAST(COALESCE(t.id_negotiation, c.id_negotiation, r.id_negotiation) AS STRING) AS sk_negotiation,
  COALESCE(t.source, c.source, r.source) AS source,
  COALESCE(t.priority, c.priority, r.priority) AS priority
FROM trato_feito_debts AS t
FULL OUTER JOIN cyber_debts AS c
  ON CAST(t.id_negotiation AS BIGINT) = CAST(c.id_negotiation AS BIGINT)
    AND t.id_invoice = c.id_invoice
FULL OUTER JOIN recupera_debts AS r
  ON CAST(t.id_negotiation AS BIGINT) = CAST(r.id_negotiation AS BIGINT)
    AND t.id_invoice = r.id_invoice
)
SELECT
  sk_debt,
  sk_negotiation,
  source,
  NOW() AS ts_load
FROM union_sources
QUALIFY ROW_NUMBER() OVER(PARTITION BY sk_debt, sk_negotiation ORDER BY priority) = 1
