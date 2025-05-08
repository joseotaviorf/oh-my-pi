WITH
base_payment AS (
  SELECT
      sk_propose AS id_propose, 
      sk_payment AS id,
      cast(due_amount as double) AS value,
      dt_created,
      date_trunc('month', dt_created) AS month_ref_creation,
      cast(dt_due as date) AS dt_due,
      date_trunc('month', dt_due) AS month_ref_due,
      cast(dt_paid as date) AS dt_paid,
      status_pay.desc_lvl_1 AS status,
      gateway.desc_lvl_1 AS gateway,
      billing.desc_lvl_1 AS billing_type,
      category.desc_lvl_1 AS category
  FROM 
    dw_velo.fact_velo_payment p
  LEFT JOIN 
    dw_velo.dim_velo_junk status_pay
      ON status_pay.sk_junk = p.sk_status
  LEFT JOIN 
    dw_velo.dim_velo_junk gateway
      ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN 
    dw_velo.dim_velo_junk billing
      ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN 
    dw_velo.dim_velo_junk category
      ON category.sk_junk = p.sk_payment_category
  WHERE 
    p.sk_payment > 0
    AND p.dt_paid <= DATE_ADD( date_trunc( 'month', CURRENT_DATE() ), -1 )
    AND status_pay.desc_lvl_1 IN ('SUCCESS')
),
payment_activation AS (
  SELECT 
    id_propose,
    sum(value) AS paid_amount_payment
  FROM 
    base_payment b
  LEFT JOIN 
    dw_velo.fact_velo_propose p
      ON b.id_propose = p.sk_propose
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv  
      ON p.sk_propose_values = pv.sk_propose_values
  WHERE 
    (
    gateway = 'WALLSTREET'
    AND billing_type = 'CREDIT_CARD'
    AND date_trunc('month',b.dt_due) = date_trunc('month',p.dt_contract_started)
    AND pv.activator_amount > 0
    )
  OR
    (
    category = 'ACTIVATION'
    AND date_trunc('month',b.dt_due) = date_trunc('month',p.dt_contract_started)
    AND activator_amount > 0
    )
  OR
    (
    b.gateway = 'ASAAS'
    AND date_trunc('month',b.dt_due) = date_trunc('month',p.dt_contract_started)
    AND pv.activator_amount > 0
    )
  GROUP BY 1
),
base_rh AS (
  SELECT distinct 
    ae.*,
    pr.status
  FROM 
    datalake_robin_hood_clean.accounting_entry ae 
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry_balance aeb 
      ON aeb.id_accounting_entry = ae.id 
  LEFT JOIN 
    datalake_robin_hood_clean.payment_request pr 
      ON pr.id = aeb.id_payment_request 
  WHERE 
    ae.id_source in (13,17) 
    AND ae.description in ('Taxa de ativação garantia', 'Debito negativo sobre a taxa de ativação')
    AND pr.status = 'paid'
    AND pr.dt_paid <= date_add(date_trunc('month',current_date()), -1)
    AND pr.id_next_attempt IS NULL 
),
payment_rh AS (
  SELECT
    SUBSTR(id_external, 1, instr(id_external, ':')-1) AS id_propose,
    sum(due_amount) AS paid_amount_rh
  FROM 
    base_rh
  GROUP BY 1
)
SELECT DISTINCT
  pro.sk_propose,
  pv.activator_amount,
  IF(pay.id_propose IS NOT NULL,pv.activator_amount,0) AS due_amount,
  coalesce(rh.paid_amount_rh,0) AS paid_amount,
  CASE 
    WHEN ( IF( pay.id_propose IS NOT NULL, pv.activator_amount, 0)) - (rh.paid_amount_rh) < 0 THEN 0
    ELSE IF( pay.id_propose IS NOT NULL, pv.activator_amount, 0) - coalesce(rh.paid_amount_rh, 0) 
  END AS open_amount,
  pro.dt_contract_started
FROM 
  dw_velo.fact_velo_propose pro
LEFT JOIN 
  dw_velo.dim_velo_propose_values pv  
    ON pro.sk_propose_values = pv.sk_propose_values
LEFT JOIN 
  dw_velo.dim_velo_propose_person pp
    ON pro.sk_primary_person = pp.sk_person
LEFT JOIN 
  payment_activation pay
    ON pay.id_propose = pro.sk_propose
LEFT JOIN  
  payment_rh rh
    ON rh.id_propose = pro.sk_propose
WHERE 
  pro.dt_contract_started IS NOT NULL
AND pro.dt_contract_started <= DATE_ADD(date_trunc('month',current_date()), -1)
AND pv.activator_amount > 0
AND pro.sk_propose > 5000000
