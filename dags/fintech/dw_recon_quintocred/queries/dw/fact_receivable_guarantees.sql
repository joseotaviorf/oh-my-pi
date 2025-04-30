WITH 
tickets AS (
  SELECT 
    TRIM(tm.sk_propose) as sk_propose,
    DATE_TRUNC('month', DATE(th.ts_updated)) as dt_updated_ticket,
    ARRAY_AGG(DISTINCT th.tags) as tags_in_ticket,
    SUM(CASE WHEN th.tags LIKE "%danos%" THEN 1 ELSE 0 END) as flag_tag_danos,
    ARRAY_AGG(DISTINCT th.description) as text_tickets,
    ARRAY_JOIN(ARRAY_AGG(th.sk_ticket), ', ') AS sk_ticket,
    ARRAY_JOIN(ARRAY_AGG(th.ticket_status), ', ') AS ticket_status
  FROM 
    dw_velo.fact_velo_ticket_history th 
  LEFT JOIN 
    dw_velo.fact_velo_ticket_metrics tm  
    ON th.sk_ticket = tm.sk_ticket
  WHERE 
    th.sk_group IN ('15679352265236','6751109396500', '11292731052180')
    AND th.is_last_register = true
  GROUP BY 
    1,2
),


acionamentos_rh AS (
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
    d.is_active,
    pr.status
  FROM 
    datalake_rental_guarantee_platform_clean.delinquency d 
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry ae 
    ON d.id = (get_json_object(metadata, "$.delinquency"))
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry_balance aeb 
    ON ae.id = aeb.id_accounting_entry 
  LEFT JOIN 
    datalake_robin_hood_clean.payment_request pr 
    ON aeb.id_payment_request = pr.id 
  WHERE 
    id_type IN (1,2) 
    AND pr.id_next_attempt IS NULL 
    AND d.original_value > 0
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY aeb.id_payment_request DESC) = 1
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
    sk_delinquency,
    dt_register_ajustada,
    due_amount_ajustado,
    open_amount_ajustado,
    year,
    month,
    day
  FROM 
    dw_fintech_snapshot_quintocred.quintocred_ifrs_occurrence
  WHERE 
    DATE(ts_snapshot) > DATE ('2024-04-01')

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
    sk_delinquency,
    dt_register_ajustada,
    due_amount_ajustado,
    open_amount_ajustado,
    year,
    month,
    day
  FROM 
    dw_fintech_snapshot_quintocred.quintocred_ifrs_occurrence
  WHERE 
    DATE(ts_snapshot) < DATE ('2024-04-01')
),
mis_tratament_w_closing AS (
  SELECT 
    m.*, 
    dt.month_end AS dt_closing 
  FROM 
    mis_tretament_table AS m
  LEFT JOIN
    dw_public.dim_date dt
      ON (dt.sk_date = CAST(DATE_FORMAT(m.ts_snapshot - INTERVAL '1' MONTH, 'yyyyMMdd') AS BIGINT))
),
last_snapshot_date AS (
  SELECT 
    MAX(dt_closing) AS last_dt_closing 
  FROM 
    mis_tratament_w_closing
),
last_snapshot AS (
  SELECT 
    b.* 
  FROM 
    mis_tratament_w_closing b
  JOIN 
    last_snapshot_date l
    ON b.dt_closing = l.last_dt_closing
  WHERE 
    ROUND(open_amount) > 0
    AND COALESCE(is_perdao_divida, FALSE) = FALSE
),
garantias_value AS (
  SELECT 
    sk_delinquency,
    SUM(due_amount_ajustado) AS delinquency_due_amount, 
    SUM(open_amount) AS delinquency_open_amount
  FROM 
    last_snapshot
  GROUP BY 
    1
),
garantias_saldo AS (
  SELECT 
    sk_propose,
    ARRAY_JOIN(ARRAY_AGG(provisional_group), ', ') AS provisional_group_aux,
    SUM(due_amount_ajustado) AS delinquency_due_amount, 
    SUM(open_amount) AS delinquency_open_amount
  FROM 
    last_snapshot
  GROUP BY 
    1
),
base AS ( 
  SELECT 
    o.origin_table,
    o.sk_propose, 
    o.sk_transaction,
    o.client_cpf_cnpj, 
    DATE(o.dt_register) AS dt_register, 
    o.dt_due, 
    o.dt_paid, 
    o.dias_atraso,
    o.due_amount AS due_amount,
    o.paid_amount AS paid_amount,
    o.open_amount AS open_amount,
    o.discount_value AS discount,
    o.bill_item,
    o.provisional_group,
    o.is_danos_imovel,
    COALESCE(o.sk_delinquency, a.id_delinquency) AS sk_delinquency, 
    ROUND(v.delinquency_due_amount) AS delinquency_due_amount,
    DATE(o.dt_register_ajustada) AS dt_register_ajustada, 
    o.due_amount_ajustado AS due_amount_ajustado,
    CASE WHEN o.dt_paid > o.ts_snapshot THEN o.due_amount ELSE o.open_amount_ajustado END AS open_amount_ajustado,
    o.open_amount_ajustado AS open_amount_ajustado_2,
    o.is_delinquency_renovacao,
    o.is_perdao_divida,
    o.is_contract_active, 
    o.dt_contract_started,
    o.dt_contract_ended,
    CASE 
      WHEN gs.provisional_group_aux LIKE '%Rescisão%' THEN p.dt_analyst_annulment_input 
      ELSE dt_ended 
    END AS model_dt_ended,
    o.valor_pacote,
    o.sk_propose_20,
    CASE 
      WHEN t.sk_ticket IS NULL THEN 'false' 
      ELSE 'true' 
    END AS has_tickets,
    CASE 
      WHEN a.status_pagamento = 'pagamento não encontrado' THEN 'false' 
      ELSE 'true' 
    END AS has_rh_payment,
    t.sk_ticket,
    a.id_payment_request,
    a.status_pagamento AS rh_status_pagamento, 
    a.pago_quando AS rh_dt_pagamento, 
    a.pagamento_programado_para AS rh_dt_pagamento_programado, 
    ROUND(a.valor_pago_para_imobiliaria) AS valor_pago_para_imobiliaria, 
    CASE 
      WHEN a.is_active = false AND o.sk_delinquency IS NOT NULL THEN true 
      ELSE false 
    END AS is_archived_delinquency,
    CASE 
      WHEN ROUND(a.valor_pago_para_imobiliaria) > ROUND(v.delinquency_due_amount) THEN 'overpaid' 
      WHEN ROUND(a.valor_pago_para_imobiliaria) = ROUND(v.delinquency_due_amount) THEN 'ok'
      WHEN ROUND(a.valor_pago_para_imobiliaria) < ROUND(v.delinquency_due_amount) THEN 'lowpaid'
    END AS check_rh_payment,
    FORMAT_NUMBER(pv.total_package_amount * pv.plan_coverage, 2) AS valor_total_garantido, 
    FORMAT_NUMBER((pv.total_package_amount * pv.plan_coverage) - gs.delinquency_due_amount, 2) AS saldo_garantia,
    o.ts_snapshot, 
    a.id_delinquency AS id_delin_rh,
    o.dt_closing
  FROM 
    last_snapshot o
  LEFT JOIN 
    garantias_value v ON v.sk_delinquency = o.sk_delinquency
  LEFT JOIN 
    tickets t ON o.sk_propose = t.sk_propose
    AND DATE_TRUNC('month', o.dt_register) = t.dt_updated_ticket
  LEFT JOIN 
    acionamentos_rh a ON a.id_delinquency = o.sk_delinquency
  LEFT JOIN 
    dw_velo.fact_velo_propose p ON o.sk_propose = p.sk_propose 
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv ON p.sk_propose_values = pv.sk_propose_values
  LEFT JOIN 
    garantias_saldo gs ON gs.sk_propose = o.sk_propose
) 
SELECT  
  m.sk_propose,
  m.sk_propose_20,
  m.sk_delinquency, 
  m.sk_transaction,
  m.sk_ticket,
  m.id_payment_request,
  m.id_delin_rh AS id_rh_delinquency,
  m.origin_table,
  m.client_cpf_cnpj AS customer_document, 
  m.bill_item,
  m.provisional_group,
  m.rh_status_pagamento AS status_rh_payment, 
  f2.description,
  m.due_amount,
  m.paid_amount,
  m.open_amount,
  m.discount AS discount_amount,
  m.delinquency_due_amount AS due_amount_delinquency, 
  m.due_amount_ajustado AS due_amount_adjusted,
  m.open_amount_ajustado_2 AS open_amount_adjusted,
  m.valor_pacote AS package_amount,
  m.valor_pago_para_imobiliaria AS paid_amount_real_estate, 
  m.check_rh_payment,
  m.valor_total_garantido AS total_amount_guaranteed, 
  m.saldo_garantia AS balance_guarantee,
  m.is_danos_imovel AS is_property_damage,
  m.is_delinquency_renovacao AS is_delinquency_renewal,
  m.is_perdao_divida AS is_debt_forgiveness,
  m.is_contract_active, 
  m.is_archived_delinquency,
  m.has_tickets,
  m.has_rh_payment,
  m.dias_atraso AS days_late,
  m.dt_register, 
  m.dt_due, 
  m.dt_paid, 
  m.dt_register_ajustada AS dt_register_adjusted, 
  m.dt_contract_started,
  m.dt_contract_ended,
  m.model_dt_ended AS dt_model_ended,
  m.rh_dt_pagamento AS dt_rh_payment, 
  m.rh_dt_pagamento_programado AS dt_rh_payment_programmed, 
  m.dt_closing,
  m.ts_snapshot,
  NOW() AS ts_load
FROM 
  base AS m
LEFT JOIN 
  datalake_rental_guarantee_platform_clean.delinquency AS f ON f.id = m.sk_delinquency
LEFT JOIN 
  datalake_rental_guarantee_platform_clean.delinquency_entry AS f2 ON f2.id = m.sk_transaction
WHERE 
  dt_register <= LAST_DAY(ts_snapshot - INTERVAL '1' MONTH)
