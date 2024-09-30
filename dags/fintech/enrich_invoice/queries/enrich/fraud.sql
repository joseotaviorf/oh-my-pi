WITH
fraudulent_invoices AS (
  SELECT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    i.purpose,
    i.country_code,
    i.status AS invoice_status,
    ii.invoice_user AS user,
    c.status AS contract_status,
    c.guarantee_type AS contract_guarantee,
    ABS(b.value_sign_bill_item) AS due_amount,
    i.accrual_year_month,
    i.dt_due_adjusted AS dt_invoice_due_adjusted,
    DATE(i.ts_created) AS dt_invoice_creation,
    LAST_DAY(b.dt_created) AS dt_month_write_off,
    b.dt_created AS dt_invoice_write_off,
    c.dt_termination AS dt_contract_annulment,
    c.ts_signed AS ts_contract_signature
  FROM datalake_retsuko.invoice AS i
  INNER JOIN datalake_retsuko.bill_items AS b
    ON i.id_external = b.id_invoice
  LEFT JOIN datalake_retsuko.invoice_info AS ii
    ON i.id_external = ii.id_invoice
  LEFT JOIN datalake_ebdb_contract.contract AS c
    ON c.id = i.id_contract_external
  WHERE
    i.status = "not-payable"
    AND b.bill_item LIKE "%LOSS%"
    AND LOWER(b.bill_item_description) LIKE "%ação boletos%"
    AND b.value_sign_bill_item <0
),
fraudulent_contracts AS (
  SELECT DISTINCT id_contract
  FROM fraudulent_invoices
),
contract_min_due_date AS (
  SELECT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    i.status,
    i.dt_due_adjusted AS dt_due_oldest_invoice,
    fi.dt_month_write_off AS dt_oldest_month_write_off,
    IF(fi.id_invoice IS NOT NULL, TRUE, FALSE) AS is_invoice_fraudulent
  FROM datalake_retsuko.invoice AS i
  INNER JOIN fraudulent_contracts AS fc
    ON i.id_contract_external = fc.id_contract
  LEFT JOIN fraudulent_invoices AS fi
    ON i.id_external = fi.id_invoice
  WHERE
    i.status = 'open'
    OR fi.id_invoice IS NOT NULL
  QUALIFY ROW_NUMBER() OVER(PARTITION BY i.id_contract_external ORDER BY i.dt_due_adjusted) = 1
)
SELECT
  i.id_contract,
  i.id_invoice,
  i.purpose,
  i.country_code,
  i.invoice_status,
  i.user,
  i.contract_status,
  i.contract_guarantee,
  i.due_amount,
  i.accrual_year_month,
  DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) AS delay_contamined_days,
  CASE
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) IS NULL THEN NULL
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 0   THEN "a. Current"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 30  THEN "b. 1-30"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 60  THEN "c. 31-60"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 90  THEN "d. 61-90"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 120 THEN "e. 91-120"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 150 THEN "f. 121-150"
      WHEN DATE_DIFF(c.dt_oldest_month_write_off, c.dt_due_oldest_invoice) <= 180 THEN "g. 151-180"
      ELSE "h. over 180"
  END AS delay_contamined_range,
  c.dt_oldest_month_write_off,
  c.dt_due_oldest_invoice,
  i.dt_invoice_due_adjusted,
  i.dt_invoice_creation,
  i.dt_month_write_off,
  i.dt_invoice_write_off,
  i.dt_contract_annulment,
  i.ts_contract_signature
FROM fraudulent_invoices AS i
LEFT JOIN contract_min_due_date As c
  ON i.id_contract = c.id_contract
