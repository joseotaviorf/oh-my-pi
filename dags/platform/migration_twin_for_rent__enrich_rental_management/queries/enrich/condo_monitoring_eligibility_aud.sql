WITH
last_record AS (
  SELECT
    id,
    id_contract,
    rev_type,
    eligibility,
    ts_created,
    ts_updated
  FROM
    datalake_rental_management.condo_monitoring_eligibility_aud
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),

ordered_cdc AS (
  SELECT
    id,
    contract_id AS id_contract,
    eligibility,
    created_at AS ts_created,
    ts_database_transaction AS ts_updated,
    op_cdc,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_database_transaction) AS rn
  FROM
    datalake_rental_management_transactional.condo_monitoring_eligibility
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
    eligibility,
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
    eligibility,
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
    eligibility,
    ts_created,
    ts_updated,
    op_cdc,
    rn,
    LAG(id_contract) OVER (PARTITION BY id ORDER BY rn) AS prev_id_contract,
    LAG(eligibility) OVER (PARTITION BY id ORDER BY rn) AS prev_eligibility
  FROM
    combined
)

SELECT
  id,
  id_contract,
  eligibility,
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
    OR eligibility != prev_eligibility
  )
