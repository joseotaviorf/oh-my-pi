WITH base_cte AS (
  SELECT
    *,
    CASE
      WHEN (
        from_account_type = 'contract'
        AND to_account_type <> 'contract') THEN (-1.0) * value_sign_bill_item
      ELSE 1.0 * value_sign_bill_item
    END AS value_sign_bill_item_fixed
  FROM
    datalake_retsuko.bill_items AS m
  WHERE
    m.due_amount <=0 AND m.bill_item IN ('EVICTIONS-DEBT-RELIEF', 'EVICTIONS-DEBT-RELIEF-NEGOTIATION')
),
forgiven_value_table AS (
  SELECT
    id_contract,
    id_invoice,
    sum(value_sign_bill_item_fixed)*(-1) AS amount_forgiven
  FROM
    base_cte
  GROUP BY 1,2
)
SELECT
  m.*,
  f.accrual_year_month,
  f.purpose,
  'ONLINE' AS origin_factor,
  cast(f.ts_created AS date) AS dt_created,
  cast(f.ts_due AS date) AS dt_due
FROM
  forgiven_value_table AS m
LEFT JOIN
  datalake_retsuko.invoice AS f ON m.id_invoice = f.id_external
UNION
SELECT
  id_contract,
  id_invoice,
  due_amount AS amount_forgiven,
  accrual_year_month,
  purpose,
  origin_factor,
  dt_created,
  dt_due_current AS dt_due
FROM
  datalake_pdd.pdd_aux_table
