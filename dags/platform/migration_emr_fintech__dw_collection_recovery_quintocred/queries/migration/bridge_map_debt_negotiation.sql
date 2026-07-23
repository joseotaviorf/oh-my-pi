WITH deduplicate_creditor_pending AS (
  SELECT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM (
    SELECT DISTINCT
      id_creditor,
      id_contract,
      id_installment AS id_invoice,
      IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
      ROW_NUMBER() OVER (PARTITION BY id_installment, installment_code ORDER BY dt_table_insertion DESC, ts_load DESC) AS _w,
      id_installment,
      installment_code,
      dt_table_insertion,
      ts_load
    FROM datalake_recupera_clean.creditor_pending
    WHERE
      NOT installment_code IS NULL
  ) AS _t
  WHERE
    _w = 1
), deduplicate_complementary_records AS (
  SELECT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM (
    SELECT DISTINCT
      id_creditor,
      id_contract,
      id_installment AS id_invoice,
      IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
      ROW_NUMBER() OVER (PARTITION BY id_installment, installment_code ORDER BY ts_last_debt_update DESC) AS _w,
      id_installment,
      installment_code,
      ts_last_debt_update
    FROM datalake_recupera_clean.complementary_records
    WHERE
      NOT installment_code IS NULL
  ) AS _t
  WHERE
    _w = 1
), deduplicate_complementary_records_written_down AS (
  SELECT
    id_creditor,
    id_contract,
    id_invoice,
    id_negotiation
  FROM (
    SELECT DISTINCT
      id_creditor,
      id_contract,
      id_installment AS id_invoice,
      IF(ASCII(TRIM(installment_code)) = 0, NULL, installment_code) AS id_negotiation,
      ROW_NUMBER() OVER (PARTITION BY id_installment, installment_code ORDER BY ts_last_debt_update DESC) AS _w,
      id_installment,
      installment_code,
      ts_last_debt_update
    FROM datalake_recupera_clean.complementary_records_written_down
    WHERE
      NOT installment_code IS NULL
  ) AS _t
  WHERE
    _w = 1
), trato_feito_debts AS (
  SELECT
    id_invoice,
    id_negotiation,
    id_contract
  FROM (
    SELECT
      d.id_external AS id_invoice,
      n.id_negotiation_external AS id_negotiation,
      n.id_contract,
      ROW_NUMBER() OVER (PARTITION BY n.id_contract, d.id_external, n.id_negotiation_external ORDER BY d.ts_created DESC) AS _w,
      d.id_external,
      d.ts_created
    FROM datalake_trato_feito_clean.debt AS d
    LEFT JOIN datalake_debt_recovery.negotiation AS n
      ON d.id_negotiation = n.id_negotiation
    WHERE
      NOT d.id_negotiation IS NULL
  ) AS _t
  WHERE
    _w = 1
), recupera_debts AS (
  SELECT
    COALESCE(cp.id_invoice, cr.id_invoice, crwd.id_invoice) AS id_invoice,
    COALESCE(cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract,
    COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) AS id_negotiation
  FROM deduplicate_creditor_pending AS cp
  FULL OUTER JOIN deduplicate_complementary_records AS cr
    ON cp.id_contract = cr.id_contract
    AND cp.id_invoice = cr.id_invoice
    AND cp.id_negotiation = cr.id_negotiation
  FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
    ON cp.id_contract = crwd.id_contract
    AND cp.id_invoice = crwd.id_invoice
    AND cp.id_negotiation = crwd.id_negotiation
  WHERE
    NOT COALESCE(cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) IS NULL
), debts AS (
  SELECT
    COALESCE(tfd.id_contract, rd.id_contract) AS id_contract,
    COALESCE(tfd.id_invoice, rd.id_invoice) AS id_invoice,
    COALESCE(tfd.id_negotiation, rd.id_negotiation) AS id_negotiation
  FROM trato_feito_debts AS tfd
  FULL OUTER JOIN recupera_debts AS rd
    ON rd.id_contract = tfd.id_contract
    AND rd.id_invoice = tfd.id_invoice
    AND rd.id_negotiation = tfd.id_negotiation
)
SELECT DISTINCT
  CONCAT(id_contract, '-', id_invoice) AS sk_debt,
  id_negotiation AS sk_negotiation,
  NOW() AS ts_load
FROM debts
