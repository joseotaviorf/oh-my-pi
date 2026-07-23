WITH
base_payment AS (
  SELECT
    sk_propose AS id_propose, 
    sk_payment AS id,
    cast(due_amount AS DOUBLE) AS value,
    dt_created,
    date_trunc('month', dt_created) AS month_ref_creation,
    cast(dt_due AS DATE) AS dt_due,
    date_trunc('month', dt_due) AS month_ref_due,
    cast(dt_paid as date) AS dt_paid,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category,
    p.ts_updated
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
    AND status_pay.desc_lvl_1 IN ('SUCCESS','REFUNDED','REFUND_PROCESSING','CHARGEBACK','REVERSED','SCHEDULED_REVERSAL')
),
payment_activation AS (
  SELECT 
    b.*
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
    AND pv.activator_amount 
    > 0
    )
  QUALIFY 
    row_number() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) = 1
)
SELECT DISTINCT
  pro.sk_propose,
  substr( ae.id_external, 1, instr( ae.id_external, ':')-1) AS sk_propose_rh,
  pr.id AS our_number, 
  pp.name AS tenant_name,
  pay.gateway,
  pay.billing_type,
  pay.status AS status_payment,
  ae.type AS type_rh,
  pr.status AS payment_status_rh, 
  ae.source_bill_item,
  ae.description,
  p.payee_name AS holder_name, 
  p.payee_document AS holder_document, 
  p.payee_bank_code AS holder_bank, 
  p.payee_agency AS holder_agency, 
  p.payee_account AS holder_account, 
  CASE 
    WHEN p.has_payee_savings_acc = TRUE THEN 'Poupança' 
    WHEN p.has_payee_savings_acc = FALSE THEN 'Conta Corrente' 
  END AS type_account, 
  p.company_use AS your_number, 
  CASE 
    WHEN p.status = ':payment.status/paid' THEN 'Pago' 
    WHEN p.status = ':payment.status/scheduled' THEN 'Agendado' 
    WHEN p.status = ':payment.status/processed' THEN 'Processado' 
    WHEN p.status = ':payment.status/error' THEN 'Erro' 
    WHEN p.status = ':payment.status/chargeback' THEN 'Estornado' 
    WHEN p.status = ':payment.status/requested' THEN 'Arquivo gerado' 
    WHEN p.status = ':payment.status/canceled' THEN 'Cancelado' 
    ELSE p.status 
  END AS status, 
  p.occurrence_code, 
  CASE 
    WHEN p.style = '05' THEN 'Crédito em Conta Poupança' 
    WHEN p.style = '01' THEN 'Crédito em Conta Corrente' 
    WHEN p.style = '41' THEN 'TED' 
    WHEN p.style = '03' THEN 'DOC' 
    WHEN p.style = '45' THEN 'PIX' 
    ELSE p.style 
  END AS payment_type, 
  b.name AS paying_bank, 
  bp.agency AS paying_agency, 
  bp.account AS paying_account, 
  bp.account_digit AS paying_digit,
  pv.activator_amount,
  pv.monthly_guarantee,
  pay.value AS payment_value,
  IF( pay.id_propose IS NOT NULL, pv.activator_amount,0) AS payment_activation,
  ae.due_amount AS paid_value_rh,
  DATE_DIFF( coalesce( pro.dt_ended_official, CURRENT_DATE), pro.dt_contract_started) AS days_contract_life,
  pro.dt_contract_started,
  pro.dt_ended_official,
  pay.dt_due AS dt_due_payment,
  pay.dt_paid AS dt_paid_payment,
  DATE(ae.ts_created) AS dt_created_rh,
  DATE(pr.dt_due) AS dt_due_rh, 
  CASE pr.status 
    WHEN 'paid' THEN pr.dt_paid 
    ELSE NULL
  END AS dt_paid_rh
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
  datalake_robin_hood_clean.accounting_entry ae 
    ON SUBSTR(ae.id_external, 1, instr(ae.id_external, ':')-1) = CAST(pro.sk_propose AS VARCHAR(10)) 
    AND ae.id_source in (13,17) 
    AND ae.description IN ('Taxa de ativação garantia',
      'Debito negativo sobre a taxa de ativação','Debito negativo sobre a taxa de ativação')
LEFT JOIN 
  datalake_robin_hood_clean.accounting_entry_balance aeb 
    ON aeb.id_accounting_entry = ae.id 
LEFT JOIN 
  datalake_robin_hood_clean.payment_request pr 
    ON pr.id = aeb.id_payment_request 
LEFT JOIN 
  datalake_vans_clean.payment p
    ON pr.id = p.id_related_document
LEFT JOIN
  datalake_vans_clean.bank_payment bp 
    ON bp.id = p.id_bank_payment 
LEFT JOIN 
  datalake_vans_clean.bank b 
    ON b.id = bp.id_bank
WHERE 
  pro.dt_contract_started IS NOT NULL
  AND pv.activator_amount > 0
  AND pr.id_next_attempt IS NULL
  AND pro.sk_propose > 5000000
