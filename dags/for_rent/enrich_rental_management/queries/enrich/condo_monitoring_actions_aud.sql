WITH
last_record AS (
  SELECT
    id,
    id_contract,
    id_action_main_user,
    action_type,
    action_main_user_email,
    action_system,
    invoice_user_name,
    invoice_user_document,
    invoice_issuer_name,
    invoice_issuer_document,
    ts_created,
    ts_updated
  FROM
    datalake_rental_management.condo_monitoring_actions_aud
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),

ordered_cdc AS (
  SELECT
    id,
    contract_id AS id_contract,
    action_main_user_id AS id_action_main_user,
    action_type,
    action_main_user_email,
    action_system,
    boleto_user_name AS invoice_user_name,
    boleto_user_document AS invoice_user_document,
    boleto_issuer_name AS invoice_issuer_name,
    boleto_issuer_document AS invoice_issuer_document,
    created_at AS ts_created,
    ts_database_transaction AS ts_updated,
    op_cdc,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_database_transaction) AS rn
  FROM
    datalake_rental_management_transactional.condo_monitoring_actions
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
    id_contract,
    id_action_main_user,
    action_type,
    action_main_user_email,
    action_system,
    invoice_user_name,
    invoice_user_document,
    invoice_issuer_name,
    invoice_issuer_document,
    ts_created,
    NULL AS ts_updated,
    NULL AS op_cdc,
    0 AS rn
  FROM
    last_record

  UNION ALL

  SELECT
    id,
    id_contract,
    id_action_main_user,
    action_type,
    action_main_user_email,
    action_system,
    invoice_user_name,
    invoice_user_document,
    invoice_issuer_name,
    invoice_issuer_document,
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
    id_contract,
    id_action_main_user,
    action_type,
    action_main_user_email,
    action_system,
    invoice_user_name,
    invoice_user_document,
    invoice_issuer_name,
    invoice_issuer_document,
    ts_created,
    ts_updated,
    op_cdc,
    rn,
    LAG(id_contract) OVER (PARTITION BY id ORDER BY rn) AS prev_id_contract,
    LAG(id_action_main_user) OVER (PARTITION BY id ORDER BY rn) AS prev_id_action_main_user,
    LAG(action_type) OVER (PARTITION BY id ORDER BY rn) AS prev_action_type,
    LAG(action_main_user_email) OVER (PARTITION BY id ORDER BY rn) AS prev_action_main_user_email,
    LAG(action_system) OVER (PARTITION BY id ORDER BY rn) AS prev_action_system,
    LAG(invoice_user_name) OVER (PARTITION BY id ORDER BY rn) AS prev_invoice_user_name,
    LAG(invoice_user_document) OVER (PARTITION BY id ORDER BY rn) AS prev_invoice_user_document,
    LAG(invoice_issuer_name) OVER (PARTITION BY id ORDER BY rn) AS prev_invoice_issuer_name,
    LAG(invoice_issuer_document) OVER (PARTITION BY id ORDER BY rn) AS prev_invoice_issuer_document
  FROM
    combined
)

SELECT
  id,
  id_contract,
  id_action_main_user,
  action_type,
  action_main_user_email,
  action_system,
  invoice_user_name,
  invoice_user_document,
  invoice_issuer_name,
  invoice_issuer_document,
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
  AND (COALESCE(id_contract, -1) != COALESCE(prev_id_contract, -1)
    OR COALESCE(id_action_main_user, -1) != COALESCE(prev_id_action_main_user, -1)
    OR action_type != prev_action_type
    OR action_main_user_email != prev_action_main_user_email
    OR action_system != prev_action_system
    OR invoice_user_name != prev_invoice_user_name
    OR action_system != prev_action_system
    OR invoice_user_name != prev_invoice_user_name
    OR invoice_user_document != prev_invoice_user_document
    OR invoice_issuer_name != prev_invoice_issuer_name
    OR invoice_issuer_document != prev_invoice_issuer_document
  )
