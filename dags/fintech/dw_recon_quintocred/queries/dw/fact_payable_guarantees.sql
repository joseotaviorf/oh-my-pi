WITH acionamentos_rh AS (
  SELECT
    d.id_propose AS id_proposta,
    aeb.id_payment_request,
    d.is_active,
    d.id AS id_delinquency,
    ae.id AS account_entry,
    ae.dt_occurrence AS data_vencimento,
    pr.id AS id_do_pagamento,
    pr.dt_paid AS pago_quando,
    d.dt_payment_scheduled AS pagamento_programado_para,
    d.original_value AS original_value_delinquency,
    CASE 
      WHEN (pr.dt_due < CURRENT_DATE AND pr.status IN ('created', 'scheduled') AND pr.ts_canceled IS NULL AND pr.id_next_attempt IS NULL) THEN 'pagamento pendente' 
      WHEN pr.ts_canceled IS NOT NULL THEN 'cancelado' 
      WHEN ae.due_amount < 0 THEN 'cancelado' 
      WHEN pr.status = 'paid' THEN 'pago' 
      WHEN pr.status = 'chargeback' THEN 'dados bancários inválidos' 
      WHEN pr.status = 'not-payable' THEN 'sem dados bancários' 
      WHEN pr.status = 'error' THEN 'erro no pagamento' 
      WHEN pr.status = 'created' THEN 'criado' 
      WHEN pr.status = 'scheduled' THEN 'agendado' 
      WHEN aeb.id_payment_request IS NULL THEN 'pagamento não encontrado'
      ELSE pr.status
    END AS status_pagamento,
    CASE 
      WHEN ae.due_amount < 0 THEN 0 
      ELSE ae.due_amount 
    END AS valor_pago_para_imobiliaria,
    pr.status
  FROM 
    datalake_rental_guarantee_platform_clean.delinquency d 
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry ae 
      ON d.id = (GET_JSON_OBJECT(metadata, "$.delinquency"))
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry_balance aeb 
      ON ae.id = aeb.id_accounting_entry 
  LEFT JOIN 
    datalake_robin_hood_clean.payment_request pr 
      ON aeb.id_payment_request = pr.id 
  WHERE 
    1 = 1 
    AND id_type IN (1, 2) 
    AND pr.id_next_attempt IS NULL 
    AND d.original_value > 0
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY aeb.id_accounting_entry DESC, pr.ts_created DESC, pr.ts_updated DESC) = 1
),
mis_tretament_table AS ( 
  SELECT  
    origin_table,
    sk_propose,
    sk_transaction,
    client_cpf_cnpj,
    dt_register_ajustada AS dt_register,
    dt_due,
    CASE WHEN open_amount > 0 THEN NULL ELSE dt_paid END AS dt_paid_ajust,
    dt_paid,
    dias_atraso,
    due_amount_ajustado AS due_amount, 
    paid_amount,
    open_amount_ajustado AS open_amount, 
    discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    ts_snapshot,
    sk_propose_20,
    is_delinquency_renovacao,
    is_perdao_divida,
    CASE 
      WHEN sk_delinquency IS NOT NULL THEN sk_delinquency
      WHEN origin_table = 'delinquency' THEN sk_transaction
      ELSE NULL 
    END AS sk_delinquency,
    dt_register_ajustada,
    due_amount_ajustado,
    open_amount_ajustado,
    year,
    month,
    day
  FROM 
    dw_fintech_snapshot_quintocred.quintocred_ifrs_occurrence
  WHERE 
    DATE(ts_snapshot) > DATE '2024-04-01'

  UNION ALL 

  SELECT  
    origin_table,
    sk_propose,
    sk_transaction,
    client_cpf_cnpj,
    dt_register,
    dt_due,
    CASE WHEN open_amount > 0 THEN NULL ELSE dt_paid END AS dt_paid_ajust,
    dt_paid,
    dias_atraso,
    due_amount,
    paid_amount,
    open_amount,
    discount_value,
    bill_item,
    provisional_group,
    is_danos_imovel,
    is_contract_active,
    dt_contract_started,
    dt_contract_ended,
    valor_pacote,
    ts_snapshot,
    sk_propose_20,
    is_delinquency_renovacao,
    is_perdao_divida,
    CASE 
      WHEN sk_delinquency IS NOT NULL THEN sk_delinquency
      WHEN origin_table = 'delinquency' THEN de.id_delinquency
      ELSE NULL 
    END AS sk_delinquency,
    CASE 
      WHEN dt_register_ajustada IS NOT NULL THEN dt_register_ajustada
      WHEN origin_table = 'delinquency' THEN dt_register
      ELSE NULL 
    END AS dt_register_ajustada,
    CASE 
      WHEN due_amount_ajustado IS NOT NULL THEN due_amount_ajustado
      WHEN origin_table = 'delinquency' THEN due_amount
      ELSE NULL 
    END AS due_amount_ajustado,
    open_amount_ajustado,
    year,
    month,
    day
  FROM 
    dw_fintech_snapshot_quintocred.quintocred_ifrs_occurrence AS m
  LEFT JOIN (
    SELECT DISTINCT 
      id AS id_de, 
      id_delinquency 
    FROM 
      datalake_rental_guarantee_platform_clean.delinquency_entry
  ) AS de 
    ON de.id_de = m.sk_transaction 
    AND m.origin_table = 'delinquency'
  WHERE 
    DATE(ts_snapshot) < DATE '2024-04-01'
),
mis_tratament_w_closing AS (
  SELECT 
    m.*, 
    dt.month_end AS dt_closing 
  FROM 
    mis_tretament_table AS m
  LEFT JOIN 
    dw_public.dim_date dt 
    ON dt.sk_date = CAST(DATE_FORMAT(m.ts_snapshot - INTERVAL '1' MONTH, 'yyyyMMdd') AS BIGINT)
),
calendario AS (
  SELECT DISTINCT 
    month_start 
  FROM 
    dw_public.dim_date  
  WHERE 
    date BETWEEN DATE '2019-01-01' AND CURRENT_DATE
),
robin_hood AS (
  SELECT 
    ca.month_start,
    r.id_proposta,
    r.id_payment_request,
    r.is_active,
    r.id_delinquency,
    r.account_entry,
    r.data_vencimento,
    r.id_do_pagamento,
    r.pagamento_programado_para,
    CASE 
      WHEN DATE_TRUNC('month', r.pago_quando) > ca.month_start THEN NULL 
      ELSE r.pago_quando 
    END AS pago_quando,
    CASE 
      WHEN DATE_TRUNC('month', r.pago_quando) > ca.month_start AND r.status_pagamento = 'pago' THEN 'pagamento_pendente' 
      ELSE r.status_pagamento 
    END AS status_pagamento,
    CASE 
      WHEN DATE_TRUNC('month', r.pago_quando) > ca.month_start THEN 0 
      ELSE r.valor_pago_para_imobiliaria 
    END AS valor_pago_para_imobiliaria,
    r.status
  FROM 
    calendario ca 
  LEFT JOIN 
    acionamentos_rh r 
    ON 1 = 1
),
garantias_saldo AS (
  SELECT 
    sk_propose,
    sk_delinquency,
    client_cpf_cnpj,
    is_perdao_divida,
    DATE(ts_snapshot) AS ts_snapshot,
    dt_closing,
    ARRAY_JOIN(ARRAY_AGG(provisional_group), ', ') AS provisional_group_aux,
    SUM(due_amount_ajustado) AS delinquency_due_amount, 
    SUM(open_amount) AS delinquency_open_amount,
    MAX(dt_register_ajustada) AS dt_register
  FROM 
    mis_tratament_w_closing
  GROUP BY 
    1, 2, 3, 4, 5, 6
),
broker_aux AS ( 
  SELECT DISTINCT 
    ca.month_start, 
    sk_broker
  FROM
    calendario ca 
  LEFT JOIN 
    dw_velo.dim_velo_broker 
    ON 1 = 1
),
status_broker AS (
  SELECT 
    ca.month_start,
    p.sk_broker, 
    COUNT(DISTINCT CASE 
      WHEN (p.dt_ended_official IS NULL OR DATE_TRUNC('month', p.dt_ended_official) >= ca.month_start) 
           AND DATE_TRUNC('month', p.dt_contract_started) <= ca.month_start 
      THEN p.sk_propose 
    END) AS active_propose,
    COUNT(DISTINCT CASE 
      WHEN COALESCE(DATE_TRUNC('month', p.dt_contract_started), DATE_TRUNC('month', CURRENT_DATE)) < ca.month_start 
      THEN sk_propose 
    END) AS total_propose
  FROM 
    broker_aux ca 
  LEFT JOIN 
    dw_velo.fact_velo_propose p 
    ON ca.sk_broker = p.sk_broker
  GROUP BY 
    1, 2
),
person AS (
  SELECT 
    p.sk_propose, 
    ARRAY_JOIN(ARRAY_AGG(pp.name), ', ') AS name
  FROM 
    dw_velo.fact_velo_propose p 
  LEFT JOIN 
    dw_velo.bridge_velo_propose_person bri 
    ON p.sk_propose = bri.sk_propose 
  LEFT JOIN 
    dw_velo.dim_velo_propose_person pp 
    ON pp.sk_person = bri.sk_person 
  WHERE 
    bri.is_primary_person = TRUE 
    AND bri.is_legacy = FALSE
  GROUP BY 
    1
)
SELECT 
  gs.sk_delinquency,
  gs.sk_propose,
  a.id_payment_request,
  per.name AS customer_name,
  gs.client_cpf_cnpj AS customer_document, 
  a.status_pagamento AS robin_hood_payment_status,
  CASE 
    WHEN gs.provisional_group_aux LIKE '%Rescisão%' THEN 'Rescisão' 
    ELSE 'Garantia' 
  END AS category, 
  CASE 
    WHEN ROUND(a.valor_pago_para_imobiliaria) > ROUND(gs.delinquency_due_amount) THEN 'overpaid' 
    WHEN ROUND(a.valor_pago_para_imobiliaria) = ROUND(gs.delinquency_due_amount) THEN 'ok'
    WHEN ROUND(a.valor_pago_para_imobiliaria) < ROUND(gs.delinquency_due_amount) THEN 'lowpaid'
  END AS check_rh_payment,
  gs.is_perdao_divida AS is_debt_forgiveness,
  CASE 
    WHEN sb.active_propose > 0 THEN TRUE 
    ELSE FALSE 
  END AS is_broker_active,
  gs.delinquency_due_amount AS original_amount,
  CASE 
    WHEN a.status_pagamento = 'pago' THEN a.valor_pago_para_imobiliaria 
    ELSE 0 
  END AS paid_amount,
  (pv.total_package_amount * pv.plan_coverage) - gs.delinquency_due_amount AS available_in_guarantee_amount,
  (pv.total_package_amount * pv.plan_coverage) AS maximum_guaranteed_amount,
  DATE_TRUNC('month', gs.dt_closing) AS reference_month_closing,
  a.pagamento_programado_para AS dt_scheduled_payment, 
  a.pago_quando AS dt_transfer, 
  a.data_vencimento AS dt_document_due,
  DATE(gs.dt_register) AS dt_delinquency_creation, 
  gs.dt_closing,
  gs.ts_snapshot
FROM 
  garantias_saldo gs 
LEFT JOIN 
  robin_hood a 
  ON a.id_delinquency = gs.sk_delinquency
  AND a.month_start = (DATE_TRUNC('month', gs.ts_snapshot) - INTERVAL '1' MONTH)
LEFT JOIN 
  dw_velo.fact_velo_propose p 
  ON gs.sk_propose = p.sk_propose 
LEFT JOIN 
  dw_velo.dim_velo_propose_values pv 
  ON p.sk_propose_values = pv.sk_propose_values
LEFT JOIN 
  status_broker sb 
  ON sb.sk_broker = p.sk_broker
  AND sb.month_start = (DATE_TRUNC('month', gs.ts_snapshot) - INTERVAL '1' MONTH)
LEFT JOIN 
  person per
  ON per.sk_propose = gs.sk_propose
WHERE 
  gs.ts_snapshot NOT IN (date('2023-11-28'), date('2024-1-12'), date('2024-6-6'), date('2024-12-12'))
  AND DATE(gs.dt_register) between date '2023-08-01' AND gs.dt_closing 
