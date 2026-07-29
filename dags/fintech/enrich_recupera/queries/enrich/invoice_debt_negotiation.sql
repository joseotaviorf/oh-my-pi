WITH deduplicate_creditor_pending_ranked AS (
  SELECT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
    ROW_NUMBER() OVER (
      PARTITION BY id_installment, installment_code
      ORDER BY dt_table_insertion DESC, ts_load DESC
    ) AS rn
  FROM datalake_recupera_clean.creditor_pending
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3, 5)
),
deduplicate_creditor_pending AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM deduplicate_creditor_pending_ranked
  WHERE rn = 1
),
deduplicate_complementary_records_ranked AS (
  SELECT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
    ROW_NUMBER() OVER (
      PARTITION BY id_installment, installment_code
      ORDER BY ts_last_debt_update DESC
    ) AS rn
  FROM datalake_recupera_clean.complementary_records
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3, 5)
),
deduplicate_complementary_records AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM deduplicate_complementary_records_ranked
  WHERE rn = 1
),
deduplicate_complementary_records_written_down_ranked AS (
  SELECT
    id_creditor,
    id_contract,
    id_installment AS id_invoice,
    IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
    ROW_NUMBER() OVER (
      PARTITION BY id_installment, installment_code
      ORDER BY ts_last_debt_update DESC
    ) AS rn
  FROM datalake_recupera_clean.complementary_records_written_down
  WHERE
    installment_code IS NOT NULL
    AND id_creditor NOT IN (3, 5)
),
deduplicate_complementary_records_written_down AS (
  SELECT DISTINCT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM deduplicate_complementary_records_written_down_ranked
  WHERE rn = 1
)
SELECT
  COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice) AS id_invoice,
  COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract,
  CAST(COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) AS BIGINT) AS id_negotiation,
  'Recupera' AS source,
  2 AS priority,
  NOW() AS ts_load
FROM deduplicate_creditor_pending AS cp
FULL OUTER JOIN deduplicate_complementary_records AS cr
  ON cp.id_contract = cr.id_contract
    AND cp.id_invoice = cr.id_invoice
    AND cp.id_negotiation = cr.id_negotiation
FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
  ON cp.id_contract = crwd.id_contract
    AND cp.id_invoice = crwd.id_invoice
    AND cp.id_negotiation = crwd.id_negotiation
WHERE COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) IS NOT NULL
