WITH
trato_feito_negotiation AS (
  SELECT
    id_negotiation_external AS id_negotiation_recupera,
    id_negotiation,
    id_contract,
    CASE
      WHEN debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
      WHEN debtor = "velo_delinquency_tenant" THEN "IQ QuintoCred"
    END AS creditor,
    is_contract_recurrent_debtor,
    status,
    has_renegotiated AS is_renegotiation,
    IF(collector = "5A-collector", TRUE, FALSE) AS is_ssn, --SSN boletão (BOSSN)
    IF(ts_first_payment IS NOT NULL, TRUE, FALSE) AS is_down_payment_paid,
    qt_installments,
    negotiation_original_amount,
    interest_fee_amount,
    fine_fee_amount,
    credit_card_fee_amount,
    ROUND(negotiation_original_amount + fine_fee_amount + interest_fee_amount, 2) AS debt_amount_without_adm_fee,
    ROUND(negotiation_original_amount + fine_fee_amount + interest_fee_amount + credit_card_fee_amount, 2) AS total_debt_amount,
    negotiation_discount_amount AS total_discount_amount, -- Total debt (total_debt_amount = original + fine + fee + credit card) - Negotiated amount (total_expected_amount)
    GREATEST(ROUND((negotiation_original_amount + fine_fee_amount + interest_fee_amount) - total_expected_amount, 2), 0) AS discount_amount_without_adm_fee, -- Total debt without credit card fee (debt_amount_without_adm_fee = original + fine + fee) - Negotiated amount (total_expected_amount)
    total_expected_amount AS negotiated_amount,
    down_payment_amount,
    paid_amount,
    INT(qt_installments_paid) AS qt_installments_paid,
    IF(breached_installment IS NOT NULL, INT(qt_installments) - INT(qt_installments_paid), 0) AS breached_installments,
    dt_expected_end,
    DATE(ts_created_at) AS dt_promisse,
    DATE(ts_first_payment) AS dt_first_payment,
    DATE(ts_paid_all) AS dt_paid_all,
    DATE(ts_breach) AS dt_breach
  FROM datalake_debt_recovery.negotiation
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_negotiation_external ORDER BY ts_created_at DESC) = 1 -- removes the exception in which 1 Trato-Feito negotiation ID has more than one Recupera negotiation ID. Ex: 97080
),
creditor_pending As (
  SELECT
    installment_code AS id_negotiation,
    id_installment AS id_invoice,
    dt_installment_due_date AS dt_due
  FROM datalake_recupera_clean.creditor_pending
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY dt_table_insertion DESC, year DESC, month DESC, day DESC)
),
original_invoices AS (
  SELECT
    COALESCE(d.id_negotiation, cp.id_negotiation) AS id_negotiation,
    COUNT(DISTINCT COALESCE(d.id_external, cp.id_invoice)) AS total_invoices_negotiated,
    MIN(COALESCE(d.dt_due, cp.dt_due)) AS dt_due_invoice_anchor
  FROM datalake_trato_feito_clean.debt AS d
  FULL OUTER JOIN creditor_pending AS cp
    ON d.id_negotiation = cp.id_negotiation
  GROUP BY 1
),
renegotiation AS (
  SELECT
    i.id_negotiation,
    IF(COUNT(DISTINCT d.id_negotiation) > 0, TRUE, FALSE) AS has_been_renegotiated
  FROM datalake_debt_recovery.installment AS i
  LEFT JOIN datalake_trato_feito_clean.accounting_installment AS ai
    ON ai.id_installment = i.id
  LEFT JOIN datalake_trato_feito_clean.debt AS d
    ON ai.id_external = d.id_external
  GROUP BY 1
),
recupera_negotiation AS (
  SELECT
    id_creditor,
    id_negotiation,
    id_contract,
    id_operator,
    customer_document,
    CASE
      WHEN negotiation_status = "ACORDO_LIQUIDADO" THEN "finished"
      WHEN negotiation_status = "ACORDO_CANCELADO"
        AND down_payment IS TRUE THEN "broken"
      WHEN negotiation_status = "ACORDO_CANCELADO"
        AND down_payment IS FALSE THEN "canceled"
      WHEN negotiation_status = "ACORDO_EM_ANDAMENTO"
        AND down_payment IS TRUE THEN "offset"
      WHEN negotiation_status = "ACORDO_EM_ANDAMENTO" THEN "started"
    END AS negotiation_status,
    is_special_installment,
    origin_agreement,
    campaign_code,
    advisory,
    agreement_type,
    agreement_in_delay,
    agreement_promise,
    promisse_payment_method,
    number_of_installments,
    paid_installments,
    breached_installments,
    down_payment,
    original_debt_amount,
    interest_fee_amount,
    adm_fee_amount AS credit_card_fee,
    fine_fee_amount AS original_fine_amount,
    GREATEST(ROUND(expense_amount - original_debt_amount - interest_fee_amount - adm_fee_amount - negotiation_discount_amount, 2), 0)  AS fine_fee_amount,
    ROUND(expense_amount - adm_fee_amount, 2) AS debt_amount_without_adm_fee, -- original_debt_amount + interest_fee_amount + fine_fee_amount
    expense_amount AS total_debt_amount, -- original_debt_amount + interest_fee_amount + fine_fee_amount + credit_card_fee
    negotiated_to_be_due_amount,
    negotiated_overdue_amount,
    negotiation_discount_amount AS original_discount_amount, -- Negotiated amount (negotiated_amount) - debt amount (total_debt_amount = expense amount = original + fine + fee + credit card)
    GREATEST(ROUND(expense_amount - negotiated_amount, 2), 0) AS discount_amount,
    GREATEST(ROUND((expense_amount - adm_fee_amount) - negotiated_amount, 2), 0) AS discount_amount_without_adm_fee, -- Negotiated amount (negotiated_amount) - debt amount without credit card fee (debt_amount_without_adm_fee = original + fine + fee = expense_amount - adm_fee_amount)
    negotiated_amount,
    down_payment_amount,
    down_payment_amount_without_fees,
    total_amount_paid,
    total_next_due,
    dt_cancellation,
    dt_next_due,
    dt_promisse,
    dt_due_promisse,
    dt_negotiation_expected_end,
    dt_down_payment,
    dt_paid_all
  FROM datalake_recupera.negotiation
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation ORDER BY ts_snapshot DESC, id_contract DESC) = 1
),
invalid_negotiations AS (
  SELECT
    id_negotiation,
    is_special_installment,
    MIN(id_contract) id_contract,
    CASE
      WHEN COUNT(DISTINCT id_contract) > 1 THEN TRUE
      WHEN is_special_installment IS TRUE THEN TRUE
      ELSE FALSE
    END AS is_invalid_negotiation,
    CASE
      WHEN COUNT(DISTINCT id_contract) > 1 THEN "Multiple contracts included in negotiation"
      WHEN is_special_installment IS TRUE THEN "Special Installment"
      ELSE NULL
    END AS invalid_reason
  FROM datalake_recupera.negotiation
  GROUP BY 1,2
),
paschoalotto_operator AS (
  SELECT DISTINCT
    d.id_contract_quintoandar AS id_contract,
    ad.id_installment AS id_negotiation,
    UPPER(u.login_name) AS id_operator,
    UPPER(u.full_name) AS operator_name,
    DATE(ad.dt_emission) AS dt_promisse
  FROM datalake_paschoalotto_clean.agreement_detail AS ad
  LEFT JOIN datalake_paschoalotto_clean.contract AS c
    ON ad.id_contract = c.id_contract
  LEFT JOIN datalake_paschoalotto_clean.debt AS d
    ON ad.id_contract = d.id_contract
  LEFT JOIN datalake_paschoalotto_clean.user AS u
      ON ad.id_user = u.id_user
  QUALIFY ROW_NUMBER() OVER(PARTITION BY d.id_contract_quintoandar, ad.id_installment ORDER BY ad.ts_update DESC) = 1
),
union_sources AS (
  SELECT
    STRING(COALESCE(tfn.id_negotiation_recupera, rn.id_negotiation)) AS sk_negotiation,
    rn.customer_document AS sk_debtor,
    tfn.id_negotiation AS id_negotiation_trato_feito,
    rn.id_negotiation AS id_negotiation_recupera,
    COALESCE(tfn.id_contract, invn.id_contract) AS id_contract,
    UPPER(rn.id_operator) AS id_operator,
    COALESCE(tfn.creditor,
      CASE
        WHEN rn.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
        WHEN rn.id_creditor IN (3,5) THEN "IQ QuintoCred"
        WHEN rn.id_creditor IN (2,6) THEN "PP QuintoAndar"
    END) AS creditor,
    invn.is_invalid_negotiation,
    invn.invalid_reason,
    rn.agreement_type,
    rn.advisory,
    rn.origin_agreement,
    rn.campaign_code,
    tfn.is_contract_recurrent_debtor AS is_recurrent_debtor,
    COALESCE(tfn.status, rn.negotiation_status) AS negotiation_status,
    CASE
      WHEN COALESCE(tfn.status, rn.negotiation_status) = "canceled" THEN "PROMESSA QUEBRADA"
      WHEN oi.total_invoices_negotiated >= 1 AND number_of_installments > 1 THEN "ACORDO"
      WHEN oi.total_invoices_negotiated > 1 AND number_of_installments = 1 THEN "QUITAÇÃO"
      WHEN oi.total_invoices_negotiated = 1 AND number_of_installments = 1 THEN "SUBSTITUIÇÃO"
      WHEN COALESCE(tfn.status, rn.negotiation_status) = "started" THEN "PROMESSA"
      ELSE "INDEFINIDO"
    END AS negotiation_classification,
    rn.agreement_promise,
    rn.promisse_payment_method,
    COALESCE(tfn.is_ssn, FALSE) AS is_ssn,
    rn.agreement_in_delay,
    COALESCE(tfn.is_down_payment_paid, rn.down_payment) AS is_down_payment_paid,
    tfn.is_renegotiation,
    r.has_been_renegotiated,
    oi.total_invoices_negotiated,
    COALESCE(tfn.qt_installments, rn.number_of_installments) AS number_of_installments,
    COALESCE(tfn.qt_installments_paid, rn.paid_installments, 0) AS paid_installments,
    COALESCE(tfn.breached_installments, rn.breached_installments, 0) AS breached_installments,
    COALESCE(tfn.negotiation_original_amount, rn.original_debt_amount) AS original_debt_amount,
    COALESCE(tfn.fine_fee_amount, IF(invn.is_invalid_negotiation IS TRUE, rn.original_fine_amount, rn.fine_fee_amount), 0) AS fine_fee_amount,
    COALESCE(tfn.interest_fee_amount, rn.interest_fee_amount, 0) AS interest_fee_amount,
    COALESCE(tfn.credit_card_fee_amount, rn.credit_card_fee, 0) AS credit_card_fee_amount,
    ROUND(COALESCE(tfn.total_debt_amount, rn.total_debt_amount), 2) AS total_debt_amount,
    COALESCE(tfn.debt_amount_without_adm_fee, rn.debt_amount_without_adm_fee) AS total_debt_amount_without_adm_fee,
    COALESCE(tfn.total_discount_amount, rn.discount_amount, 0) AS total_discount_amount, -- total debt - total negotiated. If negative then 0 else the discount amount.
    COALESCE(tfn.discount_amount_without_adm_fee, rn.discount_amount_without_adm_fee, 0) AS discount_amount_without_adm_fee,
    COALESCE(tfn.negotiated_amount, rn.negotiated_amount) AS negotiated_amount,
    rn.negotiated_to_be_due_amount,
    rn.negotiated_overdue_amount,
    COALESCE(tfn.down_payment_amount, rn.down_payment_amount) AS down_payment_amount,
    rn.down_payment_amount_without_fees,
    COALESCE(tfn.paid_amount, rn.total_amount_paid, 0) AS paid_amount,
    rn.total_next_due,
    oi.dt_due_invoice_anchor,
    COALESCE(tfn.dt_promisse, rn.dt_promisse) AS dt_promisse,
    rn.dt_due_promisse,
    COALESCE(tfn.dt_breach, rn.dt_cancellation) AS dt_cancellation,
    rn.dt_next_due,
    COALESCE(rn.dt_down_payment, tfn.dt_first_payment) AS dt_down_payment,
    COALESCE(rn.dt_paid_all, tfn.dt_paid_all) AS dt_paid_all_installments,
    COALESCE(tfn.dt_expected_end, rn.dt_negotiation_expected_end) AS dt_expected_ending,
    COALESCE(tfn.dt_breach, rn.dt_cancellation, tfn.dt_paid_all, rn.dt_paid_all) AS dt_ending,
    NOW() AS ts_load
  FROM
    recupera_negotiation AS rn
  FULL OUTER JOIN
      trato_feito_negotiation AS tfn
        ON rn.id_negotiation = tfn.id_negotiation_recupera
  LEFT JOIN
      renegotiation AS r
        ON tfn.id_negotiation = r.id_negotiation
  LEFT JOIN original_invoices AS oi
    ON tfn.id_negotiation = oi.id_negotiation
  LEFT JOIN invalid_negotiations AS invn
    ON invn.id_negotiation = rn.id_negotiation
)
SELECT
  u.sk_negotiation,
  sk_debtor,
  id_negotiation_trato_feito,
  id_negotiation_recupera,
  CAST(u.id_contract AS BIGINT) AS id_contract,
  COALESCE(po.operator_name, u.id_operator) AS id_operator,
  creditor,
  is_invalid_negotiation,
  invalid_reason,
  agreement_type,
  advisory,
  origin_agreement,
  campaign_code,
  is_recurrent_debtor,
  negotiation_status,
  negotiation_classification,
  agreement_promise,
  promisse_payment_method,
  is_ssn,
  agreement_in_delay,
  is_down_payment_paid,
  is_renegotiation,
  has_been_renegotiated,
  CASE
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 0 THEN "Current"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 30  THEN "1-30"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 60  THEN "31-60"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 90  THEN "61-90"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 120 THEN "91-120"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) <= 180 THEN "121-180"
    WHEN DATEDIFF(u.dt_promisse, dt_due_invoice_anchor) IS NULL THEN NULL
    ELSE "over 180"
  END AS delay_contamined_range,
  total_invoices_negotiated,
  number_of_installments,
  paid_installments,
  breached_installments,
  original_debt_amount,
  fine_fee_amount,
  interest_fee_amount,
  credit_card_fee_amount,
  total_debt_amount,
  total_debt_amount_without_adm_fee,
  total_discount_amount,
  discount_amount_without_adm_fee,
  ROUND(IF(total_discount_amount >= (fine_fee_amount + interest_fee_amount),
    (fine_fee_amount + interest_fee_amount),
    total_discount_amount), 2) AS discount_to_fees_amount,
  ROUND(IF(total_discount_amount >= (fine_fee_amount + interest_fee_amount),
    total_discount_amount - (fine_fee_amount + interest_fee_amount),
    0), 2) AS discount_to_original_amount,
  negotiated_amount,
  negotiated_to_be_due_amount,
  negotiated_overdue_amount,
  down_payment_amount,
  down_payment_amount_without_fees,
  paid_amount,
  total_next_due,
  DATEDIFF(dt_down_payment, dt_due_invoice_anchor) AS sla_debt_anchor_to_promisse_payment,
  DATEDIFF(u.dt_promisse, dt_due_invoice_anchor)  AS sla_debt_anchor_to_promisse,
  DATEDIFF(dt_ending, dt_down_payment) AS sla_promisse_payment_to_negotiation_ending,
  dt_due_invoice_anchor,
  u.dt_promisse,
  dt_due_promisse,
  dt_cancellation,
  dt_next_due,
  dt_down_payment,
  dt_paid_all_installments,
  dt_expected_ending,
  dt_ending,
  ts_load
FROM union_sources AS u
LEFT JOIN paschoalotto_operator AS po
  ON
    UPPER(u.id_operator) LIKE "%PASCH%"
    AND po.id_contract = u.id_contract
    AND po.id_negotiation = u.sk_negotiation
    AND po.dt_promisse = u.dt_promisse
