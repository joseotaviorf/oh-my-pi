WITH gateway_cleanup AS (
  SELECT
    *,
    CASE gateway_clean
        WHEN 'UNDEFINED' THEN NULL
        WHEN 'ASAAS' THEN 'P20'
        WHEN 'VELO_RAW_PAYMENTS' THEN 'P20'
        WHEN 'DELINQUENCY' THEN 'P30_COLL'
        WHEN 'IUGU' THEN 'P20'
        WHEN 'SAP_BILLING_DIRETO' THEN 'P30'
        WHEN 'WALLSTREET' THEN 'P30'
        WHEN 'PIXAR' THEN 'P30'
        WHEN 'OMIE' THEN 'P20'
        ELSE gateway_clean
    END AS gateway_plataform_clean
  FROM
    dw_collection_recovery.fact_quintocred_contract_payment_signature_timeline
),
step_1_cpts AS (
  SELECT
    *,
    CASE
      WHEN (gateway_plataform_clean != 'P30_COLL' OR gateway_plataform_clean IS NULL) THEN gateway_plataform_clean
      WHEN (flag_annual_payment NOT IN ('ANNUAL', 'ANNUAL+ACTIVATION') OR flag_annual_payment is null) AND birth_origin = 'is_born_2.0' THEN 'P20'
      ELSE 'P30'
    END AS current_plataform
  FROM
    gateway_cleanup
),
step_2_cpts AS (
  SELECT
    *,
    COALESCE(LAST_VALUE(current_plataform) IGNORE NULLS OVER (PARTITION BY sk_propose ORDER BY ref_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 'UNDEFINED') AS current_plataform_ffil
  FROM
    step_1_cpts
),
step_3_cpts AS (
  SELECT
  *,
  CASE
      WHEN birth_origin = 'is_born_3.0' THEN 'P30'
      WHEN birth_origin = 'is_born_2.0' AND current_plataform_ffil = 'P30' THEN 'P20_MIGRATED_P30'
      ELSE 'P20'
    END AS migration_status,
    CASE
      WHEN flag_missing_payment = 0 THEN 0
      WHEN memory_annual_valid_limit IS NOT NULL THEN 0
      WHEN memory_annual_limit IS NOT NULL AND gateway_memory_transaction = 'DELINQUENCY' AND memory_flag_annual_payment IN ('ANNUAL+ACTIVATION', 'ANNUAL') THEN 0
      ELSE flag_missing_payment
    END AS flag_missing_payment_adjs,
    CASE
      WHEN flag_missing_payment = 0 THEN 0
      WHEN memory_annual_valid_limit IS NOT NULL THEN 0
      ELSE flag_missing_payment
    END AS flag_missing_payment_adjs_v2,
    CASE
      WHEN gateway IS NOT NULL AND gateway != 'DELINQUENCY' THEN gateway
      WHEN gateway IS NOT NULL AND gateway = 'DELINQUENCY' THEN CONCAT(gateway, '_', billing_type)
      WHEN memory_annual_valid_limit IS NOT NULL OR (memory_annual_limit IS NOT NULL AND gateway_memory_transaction = 'DELINQUENCY' AND memory_flag_annual_payment IN ('ANNUAL+ACTIVATION', 'ANNUAL')) THEN CONCAT(gateway_memory_transaction, '_ANNUAL')
      ELSE 'UNFOUND'
    END AS gateway_estimation
  FROM
    step_2_cpts
),
checkpoint_step_3_cpts AS (
  SELECT
    *,
    CASE
      WHEN gateway_estimation IN ('DELINQUENCY_ANNUAL', 'DELINQUENCY_RENEWAL', 'DELINQUENCY_MONTHLY_RENEWAL') AND migration_status = 'P20' THEN 'P20_MIGRATED_P30'
      ELSE migration_status
    END AS migration_status_v2
  FROM
    step_3_cpts
),
checkpoint_stepA AS (
  SELECT
    *,
    CAST(mob AS INTEGER) % 12 AS months_since_last_renewal,
    EXTRACT(MONTH FROM dt_contract_started) AS month_of_birth,
    EXTRACT(DAY FROM dt_contract_started) AS day_of_birth,
    12 - (CAST(mob AS INTEGER) % 12) AS months_to_be_renewed,
    CAST(CAST(mob AS INTEGER) / 12 AS INTEGER) AS n_of_expected_previous_renewals
  FROM
    checkpoint_step_3_cpts
),
step_A2 AS (
  SELECT
    *,
    CASE
      WHEN n_of_expected_previous_renewals = 0 THEN 'FIRST YEAR'
      WHEN months_since_last_renewal = 0 THEN 'RENEWAL AT MONTH'
      WHEN months_since_last_renewal < EXTRACT(MONTH FROM ref_month) THEN 'RENEWED IN THIS YEAR'
      WHEN months_to_be_renewed <= (12 - EXTRACT(MONTH FROM ref_month)) THEN 'TO BE RENEWED THIS YEAR'
      ELSE 'UNDEFINED'
    END AS renewal_status
  FROM
    checkpoint_stepA
),
step_A3 AS (
  SELECT
    *,
    CASE
      WHEN renewal_status = 'FIRST YEAR' then MAKE_DATE(year(dt_contract_started)+1, month(dt_contract_started), 1)
      WHEN renewal_status = 'RENEWAL AT MONTH' then ref_month
      WHEN renewal_status = 'TO BE RENEWED THIS YEAR' then MAKE_DATE(year(ref_month), month(dt_contract_started), 1)
      ELSE MAKE_DATE(year(ref_month)+1, month(dt_contract_started), 1)
    END as expected_month_renewal
  FROM
    step_A2
),
step_A4 AS (
  SELECT
    *,
    CASE
      WHEN month_of_birth IN (1,3,5,7,8,10,12) THEN MAKE_DATE(year(expected_month_renewal), month_of_birth, day_of_birth)
      WHEN month_of_birth IN (4, 6, 9, 11) THEN MAKE_DATE(year(expected_month_renewal), month_of_birth, day_of_birth)
      WHEN month_of_birth IN (2) THEN MAKE_DATE(year(expected_month_renewal), month_of_birth, 28)
      ELSE Null
    END AS expected_day_renewal
  FROM
    step_A3
)
SELECT
  sk_propose,
  sk_broker,
  id,
  origin_table,
  status,
  gateway,
  gateway_clean,
  gateway_memory_transaction,
  gateway_plataform_clean,
  current_plataform,
  current_plataform_ffil,
  migration_status,
  migration_status_v2,
  CASE
    WHEN expected_day_renewal >= DATE('2024-9-15') AND expected_day_renewal <= DATE('2024-12-31') THEN 'Renewal Journey'
    ELSE 'Partial Link'
  END AS clean_migration_mechanism_flag,
  flag_missing_payment_adjs,
  flag_missing_payment_adjs_v2,
  gateway_estimation,
  months_since_last_renewal,
  month_of_birth,
  day_of_birth,
  months_to_be_renewed,
  n_of_expected_previous_renewals,
  renewal_status,
  id_memory_transaction,
  value_memory_transaction,
  status_memory_transaction,
  billing_type,
  category,
  birth_origin,
  status_at_ref,
  monthly_guarantee_online,
  annual_guarantee_original,
  activator_amount,
  package_amount,
  guarantee_status,
  propose_status,
  ref_mob_start,
  ref_mob_end,
  ref_month,
  number_of_distinct_gateways_at_ref,
  mob,
  property_dt_mod,
  billing_model_mod,
  monthly_value_mod,
  billing_mode_at_ref,
  monthly_guarantee,
  annual_guarantee,
  value,
  memory_annual_limit,
  memory_annual_valid_limit,
  is_billing_mode_changed,
  flag_missing_payment,
  flag_annual_payment,
  memory_flag_annual_payment,
  flag_annual_payment_month,
  flag_annual_payment_valid,
  flag_annual_payment_month_valid,
  flag_annual_payment_month_limit,
  flag_annual_payment_month_valid_limit,
  dt_created_memory_transaction,
  dt_contract_started,
  dt_ended,
  dt_created,
  dt_month_ref_creation,
  dt_due,
  dt_month_ref_due,
  dt_paid,
  expected_month_renewal AS dt_expected_month_renewal,
  expected_day_renewal AS dt_expected_day_renewal
FROM step_A4
