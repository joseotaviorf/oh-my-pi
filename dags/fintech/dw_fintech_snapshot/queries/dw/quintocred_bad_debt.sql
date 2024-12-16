WITH selected_snapshots AS (
SELECT
m.*,
dt.month_end AS dt_closing,
CAST(m.ts_snapshot AS DATE) AS dt_snapshot
FROM 
  dw_fintech_auditing.quintocred_ifrs_recurring_payment AS m
LEFT JOIN
  dw_public.dim_date dt
  ON (dt.sk_date = CAST(DATE_FORMAT(date_sub(m.ts_snapshot, 30), 'yyyyMMdd') AS BIGINT))
WHERE 
   NOT (
    ( m.year = 2023 AND m.month = 11 AND  m.day = 28 ) OR
    ( m.year = 2024 AND m.month = 1  AND  m.day = 3  ) OR
    ( m.year = 2024 AND m.month = 6  AND  m.day = 4  )
  ) 
),
step_1 AS (
SELECT *,
  CASE 
    WHEN NOT(is_contract_active) 
      AND open_amount > 0 
      AND is_delinquency_renovacao 
      THEN CAST(12*(year(dt_contract_ended) - year(dt_due)) + (month(dt_contract_ended) - month(dt_due) +1) AS DOUBLE) / 12
    WHEN is_contract_active 
      AND open_amount > 0 
      AND is_delinquency_renovacao 
      THEN CAST(12*(year(dt_closing) - year(dt_due)) + (month(dt_closing) - month(dt_due) +1) as DOUBLE) / 12
    ELSE 1 
  END AS perc_considered_base, 
  CASE 
    WHEN NOT(is_contract_active) 
      AND open_amount > 0 
      AND is_delinquency_renovacao 
      THEN CAST(12*(year(dt_contract_ended) - year(dt_due)) + (month(dt_contract_ended) - month(dt_due) +1) AS DOUBLE)
    WHEN is_contract_active 
      AND open_amount > 0 
      AND is_delinquency_renovacao 
      THEN CAST(12*(year(dt_closing) - year(dt_due)) + (month(dt_closing) - month(dt_due) +1) AS DOUBLE)
    ELSE NULL
  END AS mobs_valid_renewal_base,
  CASE 
    WHEN date_trunc('month', dt_due) = date_trunc('month', dt_closing) 
      THEN 1 
    ELSE 0 
  END AS is_emitted_at_reference_month,
  CASE 
    WHEN open_amount = 0 
      AND date_trunc('month', dt_paid) <> date_trunc('month', dt_closing)
      THEN 'OTHER'
    WHEN open_amount = 0 
      AND date_trunc('month', dt_paid) = date_trunc('month', dt_closing) 
      THEN 'PAID ATE REFERENCE MONTH'
    ELSE 'PENDING'
  END AS payment_classification
FROM 
  selected_snapshots
),
step_2 AS (
SELECT *,
  CASE 
    WHEN perc_considered_base > 1 
      THEN 1 
    ELSE perc_considered_base 
  END AS perc_considered,
  CASE 
    WHEN mobs_valid_renewal_base IS NULL 
      THEN mobs_valid_renewal_base
    WHEN mobs_valid_renewal_base > 12 
      THEN 0 
    ELSE mobs_valid_renewal_base 
  END AS mobs_valid_renewal
FROM 
  step_1
WHERE
  dt_register <= dt_closing
),
step_3 AS (
SELECT *,
  CASE 
    WHEN NOT(is_delinquency_renovacao) 
      AND date_trunc('month', dt_due) = date_trunc('month', dt_closing) 
      THEN due_amount
    WHEN (is_contract_active OR date_trunc('month', dt_contract_ended) = date_trunc('month', dt_closing)) 
      AND (mobs_valid_renewal IS NOT NULL AND mobs_valid_renewal > 0) 
      THEN due_amount/12 
    ELSE 0 
  END AS due_amount_new_bad_debt,
  CASE 
    WHEN (is_contract_active OR date_trunc('month', dt_contract_ended) = date_trunc('month', dt_closing)) 
      AND (mobs_valid_renewal IS NOT NULL AND mobs_valid_renewal > 0) 
      THEN 1 
    ELSE 0 
  END AS is_renewal_to_add_new_bad_debt
FROM 
  step_2
),
step_4 AS (
SELECT *,
  date_trunc('month', dt_closing) AS dt_reference_month,
  CASE 
    WHEN CAST(sk_propose AS INT) < 5000000 
      THEN 'PLATAFORM_2.0' 
    ELSE 'PLATAFORM_3.0' 
  END AS origin_platform,
  CASE 
    WHEN is_delinquency_renovacao 
      THEN 'RENEWAL' 
    ELSE 'SIGNATURE' 
  END AS type_deliquency,
  CASE 
    WHEN due_amount * perc_considered - paid_amount <= 0 
      THEN 0 
    ELSE due_amount * perc_considered - paid_amount 
  END AS open_amount_proportional,
  CAST(12*(year(dt_closing) - year(dt_due)) + (month(dt_closing) - month(dt_due)) AS DOUBLE) AS mob_bad_debt,
  CAST(12*(year(dt_paid) - year(dt_due)) + (month(dt_paid) - month(dt_due)) AS DOUBLE) AS mob_bad_debt_payment
FROM 
  step_3
),
step_5 AS (
SELECT *, 
  CASE 
    WHEN open_amount = 0 
      THEN open_amount 
    WHEN due_amount_new_bad_debt >= open_amount_proportional 
      THEN open_amount_proportional 
    ELSE due_amount_new_bad_debt 
  END AS open_amount_new_bad_debt,
  CASE 
    WHEN dt_paid IS NULL 
    AND mob_bad_debt > 0 
    AND dias_atraso <= 0 
      THEN DATE_DIFF( dt_due , dt_closing ) 
    ELSE dias_atraso 
  END AS days_late_bad_debt,
  CASE 
    WHEN origin_table = 'invoice' 
      THEN 'DIRECT BILLING' 
    ELSE type_deliquency 
  END AS type_deliquency_zoom
FROM 
  step_4
 ),
step_6 AS (
SELECT 
  m.*,
  f.id_type,
  CASE 
    WHEN f.id_type IS NULL 
      AND origin_table = 'invoice' 
      THEN 'BILLING DIRETO'
    WHEN f.id_type IS NULL 
      AND origin_table <> 'invoice' 
      THEN 'NOT-DELINQUENCY'
    WHEN f.id_type = 0 
      THEN 'LEGACY-SIGNATURE'
    WHEN f.id_type = 5 
      THEN 'SIGNATURE @ RENEWAL'
    WHEN f.id_type = 6 
      THEN 'SIGNATURE @ ASAAS MIGRATION'
    WHEN f.id_type = 4 
      THEN 'RENEWAL'
    ELSE  'OTHER' 
  END AS id_type_class
FROM 
  step_5 AS m
LEFT JOIN 
  datalake_rental_guarantee_platform_clean.delinquency as f 
    ON (cast(f.id AS BIGINT) = cast(m.sk_transaction AS BIGINT) 
    AND m.origin_table = 'delinquency')
)
SELECT 
  origin_table,
  origin_platform
  sk_propose,
  sk_propose_20,
  sk_transaction,
  sk_key,
  id_type,
  id_type_class
  client_cpf_cnpj,
  bill_item,
  provisional_group,
  type_deliquency,
  type_deliquency_zoom,
  payment_classification,
  due_amount,
  paid_amount,
  open_amount,
  discount_value,
  valor_pacote,
  perc_considered_base,
  perc_considered,
  due_amount_new_bad_debt,
  open_amount_proportional,
  open_amount_new_bad_debt,
  is_renewal_to_add_new_bad_debt,
  is_emitted_at_reference_month,
  is_danos_imovel,
  is_contract_active,
  is_delinquency_renovacao,
  is_perdao_divida,
  dias_atraso,
  days_late_bad_debt,
  mobs_valid_renewal_base,
  mobs_valid_renewal,
  mob_bad_debt,
  mob_bad_debt_payment,
  dt_reference_month,
  dt_closing,
  dt_snapshot,
  dt_register,
  dt_due,
  dt_paid,
  dt_contract_started,
  dt_contract_ended,
  NOW() as ts_load
FROM 
  step_6
