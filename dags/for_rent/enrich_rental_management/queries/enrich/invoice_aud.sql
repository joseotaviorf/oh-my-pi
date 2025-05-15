WITH
last_record AS (
  SELECT
    id,
    id_external,
    id_invoice_user,
    id_contract,
    value,
    status,
    raw_data,
    dt_due,
    ts_created,
    ts_updated
  FROM
    datalake_rental_management.invoice_aud
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),

ordered_cdc AS (
  SELECT
    id,
    external_id AS id_external,
    boleto_user_id AS id_invoice_user,
    contract_id AS id_contract,
    value,
    status,
    raw_data,
    due_date AS dt_due,
    created_at AS ts_created,
    ts_database_transaction AS ts_updated,
    op_cdc,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_database_transaction) AS rn
  FROM
    datalake_rental_management_transactional.boleto
  WHERE
    ( -- Condition for being on or after the start date
      year > YEAR(DATE('{load_start_date}')) OR
      (year = YEAR(DATE('{load_start_date}')) AND month > MONTH(DATE('{load_start_date}'))) OR
      (year = YEAR(DATE('{load_start_date}')) AND month = MONTH(DATE('{load_start_date}')) AND day >= DAY(DATE('{load_start_date}')))
    ) AND (-- Condition for being on or before the end date
      year < YEAR(DATE('{load_end_date}')) OR
      (year = YEAR(DATE('{load_end_date}')) AND month < MONTH(DATE('{load_end_date}'))) OR
      (year = YEAR(DATE('{load_end_date}')) AND month = MONTH(DATE('{load_end_date}')) AND day <= DAY(DATE('{load_end_date}')))
    )
),

combined AS (
  SELECT
    id,
    id_external,
    id_invoice_user,
    id_contract,
    value,
    status,
    raw_data,
    dt_due,
    ts_created,
    NULL AS ts_updated,
    NULL AS op_cdc,
    0 AS rn
  FROM
    last_record

  UNION ALL

  SELECT
    id,
    id_external,
    id_invoice_user,
    id_contract,
    value,
    status,
    raw_data,
    dt_due,
    ts_created,
    ts_updated,
    op_cdc,
    rn
  FROM
    ordered_cdc
),

sequenced_changes AS (
  SELECT
    id,
    id_external,
    id_invoice_user,
    id_contract,
    value,
    status,
    raw_data,
    dt_due,
    ts_created,
    ts_updated,
    op_cdc,
    rn,
    LAG(id_external) OVER (PARTITION BY id ORDER BY rn) AS prev_id_external,
    LAG(id_invoice_user) OVER (PARTITION BY id ORDER BY rn) AS prev_id_invoice_user,
    LAG(id_contract) OVER (PARTITION BY id ORDER BY rn) AS prev_id_contract,
    LAG(value) OVER (PARTITION BY id ORDER BY rn) AS prev_value,
    LAG(status) OVER (PARTITION BY id ORDER BY rn) AS prev_status,
    LAG(raw_data) OVER (PARTITION BY id ORDER BY rn) AS prev_raw_data,
    LAG(dt_due) OVER (PARTITION BY id ORDER BY rn) AS prev_dt_due
  FROM
    combined
)

SELECT
  id,
  id_external,
  id_invoice_user,
  id_contract,
  value,
  status,
  raw_data,
  dt_due,
  ts_created,
  ts_updated,
  CASE
    WHEN op_cdc = 'c' THEN 0
    WHEN op_cdc = 'u' THEN 1
    WHEN op_cdc = 'd' THEN 2
  END AS rev_type,
  YEAR(ts_updated) AS year,
  MONTH(ts_updated) AS month,
  DAY(ts_updated) AS day
FROM
  sequenced_changes
WHERE
  rn != 0
  AND (COALESCE(id_external, -1) != COALESCE(prev_id_external, -1)
    OR COALESCE(id_invoice_user, -1) != COALESCE(prev_id_invoice_user, -1)
    OR COALESCE(id_contract, -1) != COALESCE(prev_id_contract, -1)
    OR value != prev_value
    OR status != prev_status
    OR raw_data != prev_raw_data
    OR dt_due != prev_dt_due
  )
