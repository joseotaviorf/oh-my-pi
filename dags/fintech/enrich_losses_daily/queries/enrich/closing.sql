WITH raw_midtable_retsuko AS (
  WITH full_base AS (
    SELECT
      i.id_external AS sk_invoice,
      c.id_external AS sk_contract,
      i.status AS status,
      a.type AS user,
      i.purpose AS frequency,
      i.due_amount AS due_amount,
      i.accrual_year_month AS accrual_year_month,
      date(i.ts_created) AS dt_created,
      date(i.ts_due) AS dt_due,
      date(i.ts_paid) AS dt_paid,
      date(i.ts_canceled) AS ts_canceled
    FROM 
      datalake_retsuko.invoice AS i
    LEFT JOIN
     datalake_retsuko_clean.contract AS c 
      ON i.id_contract = c.id
    LEFT JOIN
     datalake_retsuko_clean.account AS a 
      ON i.id_account = a.id
    WHERE 
      i.due_amount <= 0 AND i.status NOT IN ('not-payable')
  ),
  ref_date AS (
    SELECT
      dd.date AS date_ref 
    FROM 
      datalake_quintoandar.aux_date AS dd
    WHERE 
      dd.date = date_sub(CAST(current_timestamp() as DATE), 1)
  ),
  full_replica AS (
    SELECT 
      * 
    FROM 
      full_base
    CROSS JOIN 
      ref_date
  )
  SELECT 
    *,
    date_ref AS closing_day,
    date_ref AS dt_snapshot,
    CASE WHEN dt_paid >= date_ref AND status = 'written-down' THEN 'wd-to-open'
      WHEN dt_paid >= date_ref AND status = 'paid' THEN 'paid-to-open'
      WHEN ts_canceled >= date_ref AND status = 'canceled' THEN 'canceled-to-open'
      ELSE status
    END AS payment_status
  FROM
    full_replica
  WHERE
     dt_created <= date_ref AND (dt_paid >= date_ref OR dt_paid IS null)
),
BASE_DIM_CONTRACT_INFO AS (
  SELECT 
    DISTINCT
    dpdc.id,
    dpdc.dt_started,
    dpdc.dt_termination,
    CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
    CASE WHEN (upper(dpdc.guarantee_type) = 'RENTALDEPOSIT' 
      OR upper(dpdc.guarantee_type) = 'RENTALGUARANTEE' 
      OR upper(dpdc.guarantee_type) = 'DEPOSITO' 
      OR upper(dpdc.guarantee_type) = 'PRO_GUARANTOR' 
      OR upper(dpdc.guarantee_type) = 'THIRDPARTYGUARANTEE' 
      OR upper(dpdc.guarantee_type) = 'STANDALONE') 
      THEN TRUE
      ELSE FALSE 
    END AS guarantee_type,
    CASE 
      WHEN(dpdc.country_code<>'BR') 
      THEN TRUE
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
BASE_INVOICES_SNAPSHOT_CLEAN_MID_POINT AS (
  SELECT 
    * 
  FROM 
    raw_midtable_retsuko
),
BASE_CLOSING_HISTORY_RAW AS (
  SELECT 
    m.*,
    CASE 
      WHEN (m.ts_canceled IS NOT NULL) AND (m.ts_canceled > closing_day) AND (m.ts_canceled <= dt_snapshot) THEN TRUE
      ELSE FALSE 
    END AS flag_canceled_in_dead_time,
    CASE 
      WHEN (payment_status = 'written down') AND (m.dt_paid > closing_day) AND (m.dt_paid <= dt_snapshot ) THEN TRUE
      ELSE FALSE 
    END AS flag_writtendown_in_dead_time,
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
    BASE_INVOICES_SNAPSHOT_CLEAN_MID_POINT AS m
  LEFT JOIN 
    BASE_DIM_CONTRACT_INFO AS c 
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
  user,
  'MIDPOINT CLOSING' as origin_factor,
  closing_day as dt_closing,
  dt_due, 
  dt_paid, 
  dt_snapshot
FROM 
  BASE_CLOSING_HISTORY_RAW
