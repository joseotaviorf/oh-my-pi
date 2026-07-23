WITH sap AS (
  SELECT
    id_finance_entity AS id_fatura,
    id_finance_entity_entry AS id_contract,
    credit AS mensalidade_por_contrato
  FROM datalake_accounting_funnel.ledger
  WHERE
    (
      account_number = '113009' OR account_name IN ('Duplicatas a Receber VELO')
    )
    AND debit = 0
), cobranca_billing AS (
  SELECT
    id_propose,
    id_boleto,
    id_fatura,
    dt_ref_boleto,
    mensalidade_por_contrato,
    total_amount,
    status_invoice,
    status_boleto,
    dt_paid,
    dt_boleto_created,
    dt_due
  FROM (
    SELECT DISTINCT
      COALESCE(sap.id_contract, e.propose) AS id_propose,
      i.id_bill AS id_boleto,
      COALESCE(sap.id_fatura, e.id_billing_report) AS id_fatura,
      ADD_MONTHS(
        CAST(CONCAT(CAST(i.accrual_year AS STRING), '-', CAST(i.accrual_month AS STRING), '-', '01') AS DATE),
        1
      ) AS dt_ref_boleto,
      COALESCE(sap.mensalidade_por_contrato, e.amount) AS mensalidade_por_contrato,
      i.total_amount,
      i.status AS status_invoice,
      b.status AS status_boleto,
      CAST(b.ts_paid AS DATE) AS dt_paid,
      CAST(b.ts_created AS DATE) AS dt_boleto_created,
      CAST(b.dt_due AS DATE) AS dt_due,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(sap.id_contract, e.propose), ADD_MONTHS(
        CAST(CONCAT(CAST(i.accrual_year AS STRING), '-', CAST(i.accrual_month AS STRING), '-', '01') AS DATE),
        1
      ) ORDER BY b.ts_paid DESC, b.ts_created DESC) AS _w,
      sap.id_contract,
      e.propose,
      b.ts_paid,
      b.ts_created
    FROM datalake_rental_guarantee_platform_clean.billing_report AS i
    LEFT JOIN datalake_rental_guarantee_platform_clean.bill AS b
      ON b.id = i.id_bill
    LEFT JOIN datalake_rental_guarantee_platform_clean.entry AS e
      ON e.id_billing_report = i.id
    LEFT JOIN datalake_rental_guarantee_platform_clean.propose AS p
      ON p.id = e.propose
    LEFT JOIN sap
      ON sap.id_fatura = CAST(i.id AS STRING) AND sap.id_contract = CAST(p.id AS STRING)
    WHERE
      NOT CONCAT(b.status, i.status) IN ('WRITTEN_DOWNCANCELED')
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_propose,
  CONCAT(id_boleto, CONCAT(id_propose, REPLACE(dt_ref_boleto, '-', ''))) AS id,
  id_boleto AS id_bill,
  'a_billing' AS origin_table,
  mensalidade_por_contrato AS value,
  CASE
    WHEN status_boleto IN ('PAID_AFTER_DUE_DATE', 'PAID', 'CONFIRMED')
    THEN value
  END AS value_paid,
  status_boleto AS status,
  CASE
    WHEN status_boleto IN ('PAID_AFTER_DUE_DATE', 'PAID')
    THEN 1
    WHEN status_boleto IN ('PROCESSING')
    THEN 2
    WHEN status_boleto IN ('OPEN')
    THEN 3
    WHEN status_boleto IN ('OVERDUE')
    THEN 4
    WHEN status_boleto IN ('WRITTEN_DOWN')
    THEN 5
    ELSE 99
  END AS order_status,
  'BILLING DIRETO' AS gateway,
  'BOLETO' AS billing_type,
  CAST(NULL AS STRING) AS category,
  CAST(dt_due AS DATE) < CURRENT_DATE AS is_overdue,
  dt_paid,
  dt_boleto_created AS dt_created,
  dt_ref_boleto AS dt_due,
  NOW() AS ts_load
FROM cobranca_billing
WHERE
  NOT id_propose IS NULL
