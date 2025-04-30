WITH
last_record AS (
  SELECT
    id,
    id_user,
    id_account_manager,
    is_active,
    ts_revision
  FROM
    datalake_aud_test.user_pro_owner_aud
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_revision DESC) = 1
),

ordered_cdc AS (
  SELECT
    id,
    account_manager_id AS id_account_manager,
    user_id AS id_user,
    active AS is_active,
    ts_database_transaction AS ts_revision,
    op_cdc,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_database_transaction) AS rn
  FROM
    datalake_ebdb_transactional.userproowner
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
    id_user,
    id_account_manager,
    is_active,
    NULL AS op_cdc,
    NULL AS ts_revision,
    0 AS rn
  FROM
    last_record

  UNION ALL

  SELECT
    id,
    id_user,
    id_account_manager,
    is_active,
    op_cdc,
    ts_revision,
    rn
  FROM
    ordered_cdc
),

sequenced_changes AS (
  SELECT
    id,
    id_user,
    id_account_manager,
    is_active,
    op_cdc,
    ts_revision,
    rn,
    LAG(id_user) OVER (PARTITION BY id ORDER BY rn) AS prev_id_user,
    LAG(id_account_manager) OVER (PARTITION BY id ORDER BY rn) AS prev_id_account_manager,
    LAG(is_active) OVER (PARTITION BY id ORDER BY rn) AS prev_is_active
  FROM
    combined
)

SELECT
  id,
  id_user,
  id_account_manager,
  is_active,
  CASE
    WHEN op_cdc = 'c' THEN 0
    WHEN op_cdc = 'u' THEN 1
    WHEN op_cdc = 'd' THEN 2
  END AS rev_type,
  ts_revision,
  YEAR(ts_revision) AS year,
  MONTH(ts_revision) AS month,
  DAY(ts_revision) AS day
FROM
  sequenced_changes
WHERE
  rn != 0
  AND (COALESCE(id_user, -1) != COALESCE(prev_id_user, -1)
    OR COALESCE(id_account_manager, -1) != COALESCE(prev_id_account_manager, -1)
    OR is_active != prev_is_active)
