WITH cte_split_bill_item AS (
  SELECT
    id,
    UPPER(REVERSE(SPLIT(bill_item, '/')) [0]) AS bill_item,
    id_invoice
  FROM
    datalake_retsuko.entry 
),
analytical_db_manual_revenue_bill_item AS (
  SELECT
    rcc.id_external AS id_contract,
    rci.id_external AS id_invoice,
    rci.purpose,
    rci.status AS payment_status,
    bi.bill_item AS bill_item,
    rce.description AS bill_item_description,
    rca.type AS from_account_type,
    rcab.type AS to_account_type,
    CASE
      WHEN (
        rca.type = 'contract'
        AND rcab.type <> 'contract'
      ) THEN (-1.0) * rce.amount
      ELSE 1.0 * rce.amount
    END AS value_sign_bill_item,
    rci.due_amount,
    rce.accrual_year_month AS accrual_year_month,
    rci.accrual_year_month AS accrual_year_month_invoice,
    CAST(rci.ts_created AS DATE) AS dt_created,
    CAST(rci.ts_sent AS DATE) AS dt_sent,
    CAST(rci.ts_due AS DATE) AS dt_due,
    CAST(rci.ts_paid AS DATE) AS dt_paid,
    CAST(rci.ts_canceled AS DATE) AS dt_canceled
  FROM
    datalake_retsuko.invoice AS rci
    LEFT JOIN cte_split_bill_item AS bi ON bi.id_invoice = rci.id
    LEFT JOIN datalake_retsuko.entry AS rce ON bi.id = rce.id
    LEFT JOIN datalake_retsuko_clean.account AS rca ON rca.id = rce.id_from_account
    LEFT JOIN datalake_retsuko_clean.account AS rcab ON rcab.id = rce.id_to_account
    LEFT JOIN datalake_retsuko_clean.contract AS rcc ON rcc.id = rci.id_contract
  WHERE
    bi.bill_item = UPPER('home-insurance')
    AND rca.type = 'tenant'
    AND rcab.type = 'contract'
    AND rci.status <> 'canceled'
    AND rci.due_amount <= 0
),
base_agg AS (
  SELECT
    id_contract,
    id_invoice,
    accrual_year_month,
    sum(value_sign_bill_item) AS raw_payment_amount
  FROM
    analytical_db_manual_revenue_bill_item
  GROUP BY
    1,
    2,
    3
),
contract_info AS (
  SELECT
    m.*,
    'MONTHLY-PAYMENT' AS origin_fact,
    dpdc.rent,
    dpdc.dt_started as dt_start,
    dpdc.dt_termination as dt_annulment,
    dpdc.guarantee_type AS guarantee
  FROM
    base_agg AS m
    LEFT JOIN datalake_ebdb_contract.contract AS dpdc ON m.id_contract = dpdc.id
  WHERE
    dpdc.status <> 'Cancelado'
),
comission_inclusion AS (
  SELECT
    *,
    CASE
      WHEN accrual_year_month <= 202205
      AND dt_start <= date('2019-05-31') THEN 0.465
      WHEN accrual_year_month <= 202205
      AND dt_start > date('2019-05-31') THEN 0.55
      WHEN accrual_year_month = 202206
      AND dt_start <= date('2019-05-31') THEN 0.55
      WHEN accrual_year_month = 202206
      AND dt_start > date('2019-05-31')
      AND dt_start <= date('2019-11-30') THEN 0.61
      WHEN accrual_year_month = 202206
      AND dt_start > date('2019-11-30') THEN 0.64
      WHEN accrual_year_month > 202206 THEN 0.64
    END AS comission_factor
  FROM
    contract_info
  WHERE
    dt_annulment IS null
    OR dt_annulment > dt_start
)
SELECT
  id_contract,
  id_invoice,
  accrual_year_month,
  comission_factor,
  guarantee,
  origin_fact,
  raw_payment_amount,
  rent,
  comission_factor * raw_payment_amount AS revenue_comission,
  dt_annulment,
  dt_start
FROM
  comission_inclusion
