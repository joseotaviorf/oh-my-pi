WITH BASE_DIM_CONTRACT_INFO AS (
  SELECT
    DISTINCT
      dpdc.sk_contract as id,
      dpdc.dt_start as dt_started,
      dpdc.dt_annulment as dt_termination,
      CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
      CASE
            WHEN (upper(dpdc.guarantee) = 'RENTALDEPOSIT'
                  OR upper(dpdc.guarantee) = 'RENTALGUARANTEE'
                  OR upper(dpdc.guarantee) = 'DEPOSITO'
                  OR upper(dpdc.guarantee) = 'PRO_GUARANTOR'
                  OR upper(dpdc.guarantee) = 'THIRDPARTYGUARANTEE'
                  OR upper(dpdc.guarantee) = 'STANDALONE')
                  THEN TRUE
            ELSE FALSE
      END AS guarantee_type,
      CASE
            WHEN(dpdc.country_code<>'BR') THEN TRUE
            ELSE FALSE
      END AS flag_is_international,
      CASE
            WHEN(dpdc.dt_annulment IS NOT NULL AND datediff(dpdc.dt_annulment, dpdc.dt_start ) <= 0) THEN TRUE
            ELSE FALSE
      END AS flag_is_before_started_raw,
      CASE
        WHEN upper(dpdc.guarantee) = 'SEGUROFAIRFAX' THEN 'Fairfax'
        WHEN upper(dpdc.guarantee) = 'PRO_GUARANTOR' THEN 'Pro_Guarantor'
        WHEN upper(dpdc.guarantee) = 'RENTALGUARANTEE' THEN 'Rental_Guarantee'
        WHEN upper(dpdc.guarantee) = 'RENTALDEPOSIT' or dpdc.guarantee = 'DEPOSITO' THEN 'Rental_Deposit'
        WHEN upper(dpdc.guarantee) = 'STANDALONE' THEN 'Standalone'
        WHEN upper(dpdc.guarantee) = 'THIRDPARTYGUARANTEE' THEN 'Third_Party_3D'
      ELSE 'Outros' END AS contract_guarantee,
      coalesce(date(dpdc.ts_signature), date(dpdc.dt_start)) as contract_signature_date,
      dt_annulment
  FROM
    dw_public_snapshot.dim_contract_snapshot AS dpdc
  WHERE
    dpdc.sk_contract<>-1 AND year = 2022 AND month  = 10 AND day = 4
),

BASE_INVOICES_SNAPSHOT_CLEAN_HISTORY AS (
  SELECT
    sk_invoice,
    sk_contract,
    accrual_year_month,
    due_amount,
    frequency,
    payment_status,
    cast(null AS DOUBLE) as paid_amount,
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
    CASE
      WHEN coalesce(c.dt_annulment, current_date) <= (date_trunc('month', m.dt_snapshot) - interval '1' day) THEN 'Finalizado'
    ELSE 'Ativo' END AS status_mes_fechamento,
    c.contract_signature_date,
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
  status_mes_fechamento AS closing_month_status,
  due_amount,
  frequency,
  CASE
    WHEN frequency = 'monthly' THEN 'Mensal'
    WHEN frequency = 'onboarding' THEN 'Onboarding'
    WHEN frequency = 'extra' THEN 'Extra'
    WHEN frequency = 'early termination' THEN 'Rescisão'
    WHEN frequency = 'pos rental' THEN 'Pos_rental'
    ELSE frequency
  END AS invoice_type,
  contract_guarantee,
  guarantee_type as is_guarantee_paid,
  flag_is_before_started as is_before_started,
  flag_is_before_started_raw as is_before_started_raw,
  flag_canceled_in_dead_time as is_canceled_in_dead_time,
  flag_is_international as is_international,
  flag_paid_in_closing_day as is_paid_in_closing_day,
  flag_writtendown_in_dead_time as is_writtendown_in_dead_time,
  paid_amount,
  payment_status,
  COALESCE(user,'tenant') AS user,
  'HISTORICAL BUILD' as origin_factor,
  closing_day as dt_closing,
  contract_signature_date as dt_contract_signature,
  dt_annulment,
  dt_due,
  dt_paid,
  CAST(null as DATE) as dt_sent,
  dt_snapshot
FROM
  BASE_CLOSING_HISTORY_RAW
