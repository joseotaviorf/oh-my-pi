WITH base_payment AS (
  SELECT
    sk_propose AS id_propose,
    sk_payment AS id,
    CAST(due_amount AS DOUBLE) AS value,
    dt_created,
    DATE_TRUNC('MONTH', dt_created) AS month_ref_creation,
    CAST(dt_due AS DATE) AS dt_due,
    DATE_TRUNC('MONTH', dt_due) AS month_ref_due,
    CAST(dt_paid AS DATE) AS dt_paid,
    status_pay.desc_lvl_1 AS status,
    gateway.desc_lvl_1 AS gateway,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category,
    p.ts_updated
  FROM dw_velo.fact_velo_payment AS p
  LEFT JOIN dw_velo.dim_velo_junk AS status_pay
    ON status_pay.sk_junk = p.sk_status
  LEFT JOIN dw_velo.dim_velo_junk AS gateway
    ON gateway.sk_junk = p.sk_payment_gateway
  LEFT JOIN dw_velo.dim_velo_junk AS billing
    ON billing.sk_junk = p.sk_billing_type
  LEFT JOIN dw_velo.dim_velo_junk AS category
    ON category.sk_junk = p.sk_payment_category
  WHERE
    p.sk_payment > 0
    AND status_pay.desc_lvl_1 IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING', 'CHARGEBACK', 'REVERSED', 'SCHEDULED_REVERSAL')
), payment_activation AS (
  SELECT
    *
  FROM (
    SELECT
      b.*,
      ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_updated DESC) AS _w
    FROM base_payment AS b
    LEFT JOIN dw_velo.fact_velo_propose AS p
      ON b.id_propose = p.sk_propose
    LEFT JOIN dw_velo.dim_velo_propose_values AS pv
      ON p.sk_propose_values = pv.sk_propose_values
    WHERE
      (
        gateway = 'WALLSTREET'
        AND billing_type = 'CREDIT_CARD'
        AND DATE_TRUNC('MONTH', b.dt_due) = DATE_TRUNC('MONTH', p.dt_contract_started)
        AND pv.activator_amount > 0
      )
      OR (
        category = 'ACTIVATION'
        AND DATE_TRUNC('MONTH', b.dt_due) = DATE_TRUNC('MONTH', p.dt_contract_started)
        AND activator_amount > 0
      )
      OR (
        b.gateway = 'ASAAS'
        AND DATE_TRUNC('MONTH', b.dt_due) = DATE_TRUNC('MONTH', p.dt_contract_started)
        AND pv.activator_amount > 0
      )
  ) AS _t
  WHERE
    _w = 1
)
SELECT DISTINCT
  pro.sk_propose,
  SUBSTRING(ae.id_external, 1, LOCATE(':', ae.id_external) - 1) AS sk_propose_rh,
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
    WHEN p.has_payee_savings_acc = TRUE
    THEN 'Poupança'
    WHEN p.has_payee_savings_acc = FALSE
    THEN 'Conta Corrente'
  END AS type_account,
  p.company_use AS your_number,
  CASE
    WHEN p.status = ':payment.status/paid'
    THEN 'Pago'
    WHEN p.status = ':payment.status/scheduled'
    THEN 'Agendado'
    WHEN p.status = ':payment.status/processed'
    THEN 'Processado'
    WHEN p.status = ':payment.status/error'
    THEN 'Erro'
    WHEN p.status = ':payment.status/chargeback'
    THEN 'Estornado'
    WHEN p.status = ':payment.status/requested'
    THEN 'Arquivo gerado'
    WHEN p.status = ':payment.status/canceled'
    THEN 'Cancelado'
    ELSE p.status
  END AS status,
  p.occurrence_code,
  CASE
    WHEN p.style = '05'
    THEN 'Crédito em Conta Poupança'
    WHEN p.style = '01'
    THEN 'Crédito em Conta Corrente'
    WHEN p.style = '41'
    THEN 'TED'
    WHEN p.style = '03'
    THEN 'DOC'
    WHEN p.style = '45'
    THEN 'PIX'
    ELSE p.style
  END AS payment_type,
  b.name AS paying_bank,
  bp.agency AS paying_agency,
  bp.account AS paying_account,
  bp.account_digit AS paying_digit,
  pv.activator_amount,
  pv.monthly_guarantee,
  pay.value AS payment_value,
  IF(NOT pay.id_propose IS NULL, pv.activator_amount, 0) AS payment_activation,
  ae.due_amount AS paid_value_rh,
  DATEDIFF(
    TO_DATE(COALESCE(pro.dt_ended_official, CURRENT_DATE)),
    TO_DATE(pro.dt_contract_started)
  ) AS days_contract_life,
  pro.dt_contract_started,
  pro.dt_ended_official,
  pay.dt_due AS dt_due_payment,
  pay.dt_paid AS dt_paid_payment,
  CAST(ae.ts_created AS DATE) AS dt_created_rh,
  CAST(pr.dt_due AS DATE) AS dt_due_rh,
  CASE pr.status WHEN 'paid' THEN pr.dt_paid ELSE NULL END AS dt_paid_rh
FROM dw_velo.fact_velo_propose AS pro
LEFT JOIN dw_velo.dim_velo_propose_values AS pv
  ON pro.sk_propose_values = pv.sk_propose_values
LEFT JOIN dw_velo.dim_velo_propose_person AS pp
  ON pro.sk_primary_person = pp.sk_person
LEFT JOIN payment_activation AS pay
  ON pay.id_propose = pro.sk_propose
LEFT JOIN datalake_robin_hood_clean.accounting_entry AS ae
  ON SUBSTRING(ae.id_external, 1, LOCATE(':', ae.id_external) - 1) = CAST(pro.sk_propose AS STRING)
  AND ae.id_source IN (13, 17)
  AND ae.description IN ('Taxa de ativação garantia', 'Debito negativo sobre a taxa de ativação', 'Debito negativo sobre a taxa de ativação')
LEFT JOIN datalake_robin_hood_clean.accounting_entry_balance AS aeb
  ON aeb.id_accounting_entry = ae.id
LEFT JOIN datalake_robin_hood_clean.payment_request AS pr
  ON pr.id = aeb.id_payment_request
LEFT JOIN datalake_vans_clean.payment AS p
  ON pr.id = p.id_related_document
LEFT JOIN datalake_vans_clean.bank_payment AS bp
  ON bp.id = p.id_bank_payment
LEFT JOIN datalake_vans_clean.bank AS b
  ON b.id = bp.id_bank
WHERE
  NOT pro.dt_contract_started IS NULL
  AND pv.activator_amount > 0
  AND pr.id_next_attempt IS NULL
  AND pro.sk_propose > 5000000
