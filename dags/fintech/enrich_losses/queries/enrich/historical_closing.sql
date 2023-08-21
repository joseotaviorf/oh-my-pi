WITH BASE_DIM_CONTRACT_INFO AS (
  SELECT 
    DISTINCT
    dpdc.id,
    dpdc.dt_started,
    dpdc.dt_termination,
    CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
    CASE 
      WHEN (upper(dpdc.guarantee_type) = 'RENTALDEPOSIT' 
        OR upper(dpdc.guarantee_type) = 'RENTALGUARANTEE' 
        OR upper(dpdc.guarantee_type) = 'DEPOSITO' 
        OR upper(dpdc.guarantee_type) = 'PRO_GUARANTOR' 
        OR upper(dpdc.guarantee_type) = 'THIRDPARTYGUARANTEE' 
        OR upper(dpdc.guarantee_type) = 'STANDALONE') 
        THEN TRUE
      ELSE FALSE 
    END AS guarantee_type,
    CASE 
          WHEN(dpdc.country_code<>'BR') THEN TRUE
          ELSE FALSE
    END AS flag_is_international,
    CASE 
          WHEN(dpdc.dt_termination IS NOT NULL AND dpdc.dt_termination <= dpdc.dt_started) THEN TRUE
          ELSE FALSE
    END AS flag_is_before_started_raw
  FROM 
    datalake_ebdb_contract.contract AS dpdc
  WHERE 
    dpdc.id<>-1
),

BASE_INVOICES_SNAPSHOT_CLEAN_HISTORY AS (
  SELECT 
    sk_invoice,
    sk_contract,
    accrual_year_month,
    due_amount,
    frequency,
    payment_status,
    user,
    cast(dt_due_retsuko as date) as dt_due,
    cast(dt_paid_og as date) as dt_paid,
    cast(data_corte as date) as closing_day,
    cast(data_corte as date) as dt_snapshot
  FROM 
    datalake_ifrs_monthly_wallet_temp.fechamentos_regras_15032023_onboarding_unchanged
  WHERE
    date_trunc('month', cast(data_corte as date))<=date('2022-06-01')),

BASE_CLOSING_HISTORY_RAW AS (
  SELECT 
    m.*,
    FALSE AS flag_canceled_in_dead_time,
    FALSE AS flag_writtendown_in_dead_time,
    CASE 
      WHEN m.dt_paid = closing_day THEN TRUE 
      ELSE FALSE
    END AS flag_paid_in_closing_day,
    CASE 
      WHEN flag_is_before_started_raw IS TRUE AND annulment_input_dt > dt_snapshot THEN FALSE
      ELSE flag_is_before_started_raw 
    END AS flag_is_before_started,
    c.*
  FROM 
    BASE_INVOICES_SNAPSHOT_CLEAN_HISTORY AS m
  LEFT JOIN BASE_DIM_CONTRACT_INFO AS c 
    ON c.id = m.sk_contract
)                            
SELECT 
  sk_invoice as id_invoice,
  sk_contract as id_contract,
  accrual_year_month,
  due_amount, 
  frequency, 
  guarantee_type as is_guarantee_paid,
  flag_is_before_started as is_before_started,
  flag_is_before_started_raw as is_before_started_raw,
  flag_canceled_in_dead_time as is_canceled_in_dead_time,
  flag_is_international as is_international,
  flag_paid_in_closing_day as is_paid_in_closing_day,
  flag_writtendown_in_dead_time as is_writtendown_in_dead_time,
  payment_status, 
  COALESCE(user,'tenant') AS user,
  'HISTORICAL BUILD' as origin_factor,
  closing_day as dt_closing,
  dt_due, 
  dt_paid, 
  dt_snapshot
FROM 
  BASE_CLOSING_HISTORY_RAW