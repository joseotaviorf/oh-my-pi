WITH
trato_feito_negotiation AS (
  SELECT
    CAST(n.id_negotiation_external AS STRING) AS id_negotiation,
    n.id_negotiation AS id_negotiation_trato_feito,
    n.id_contract,
    REGEXP_REPLACE(cl.document,r'\.|\-', '') AS id_customer,
    CASE
      WHEN LOWER(n.collector) LIKE '%cyber%' THEN "Trato Feito - Cyber"
      WHEN LOWER(n.collector) LIKE '%recupera%' THEN "Trato Feito - Recupera"
      WHEN UPPER(n.collector) LIKE '%5A%' THEN "Trato Feito - Self Service"
    END AS source,
    COUNT(n.id_contract) OVER(PARTITION BY n.id_negotiation_external) AS contracts_by_negotiation,
    CASE
      WHEN n.debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN n.debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
    n.consultancy AS advisory,
    CASE
      WHEN n.consultancy IS NOT NULL THEN "Assessoria"
      WHEN n.collector = "5A-collector" THEN "Portal Auto Negociação"
      ELSE "Operador Interno"
    END AS origin_agreement,
    n.promisse_payment_method,
    n.status,
    n.has_renegotiated AS is_renegotiation,
    IF(n.ts_first_payment IS NOT NULL, TRUE, FALSE) AS is_down_payment_paid,
    n.qt_installments,
    n.negotiation_original_amount AS original_debt_amount,
    n.interest_fee_amount,
    n.fine_fee_amount AS fine_amount,
    n.credit_card_fee_amount,
    ROUND(n.negotiation_original_amount + n.fine_fee_amount + n.interest_fee_amount, 2) AS debt_amount_without_adm_fee,
    ROUND(n.negotiation_original_amount + n.fine_fee_amount + n.interest_fee_amount + n.credit_card_fee_amount, 2) AS total_debt_amount,
    n.negotiation_discount_amount AS total_discount_amount, -- Total debt (total_debt_amount = original + fine + fee + credit card) - Negotiated amount (total_expected_amount)
    GREATEST(ROUND((n.negotiation_original_amount + n.fine_fee_amount + n.interest_fee_amount) - total_expected_amount, 2), 0) AS discount_amount_without_adm_fee, -- Total debt without credit card fee (debt_amount_without_adm_fee = original + fine + fee) - Negotiated amount (total_expected_amount)
    n.total_expected_amount AS negotiated_amount,
    n.down_payment_amount,
    n.paid_amount,
    INT(n.qt_installments_paid) AS qt_installments_paid,
    IF(n.breached_installment IS NOT NULL, INT(n.qt_installments) - INT(n.qt_installments_paid), 0) AS breached_installments,
    n.dt_expected_end,
    DATE(n.ts_created_at) AS dt_promisse,
    DATE(n.ts_first_payment) AS dt_first_payment,
    DATE(n.ts_paid_all) AS dt_paid_all,
    DATE(n.ts_breach) AS dt_breach,
    DATE(COALESCE(n.ts_breach, n.ts_paid_all)) AS dt_ending
  FROM datalake_debt_recovery.negotiation AS n
  LEFT JOIN datalake_trato_feito_clean.contract AS ct
    ON n.id_contract = ct.id_external
  LEFT JOIN datalake_trato_feito_clean.client AS cl
    ON cl.id_contract = ct.id
  WHERE n.debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY n.id_contract, n.id_negotiation_external ORDER BY n.ts_created_at DESC) = 1 -- removes the exception in which 1 Trato-Feito negotiation ID has more than one Recupera negotiation ID. Ex: 97080
),
union_external_sources AS (
  SELECT
    id_negotiation,
    id_contract_external AS id_contract,
    id_operator,
    id_customer,
    id_campaign,
    COUNT(id_contract) OVER(PARTITION BY id_negotiation) AS contracts_by_negotiation,
    "IQ QuintoAndar" AS creditor,
    negotiation_status,
    n.exception,
    origin_agreement,
    advisory,
    agreement_type,
    promisse_payment_method,
    is_down_payment_paid,
    number_of_installments,
    paid_installments,
    breached_installments,
    debt_amount AS original_debt_amount,
    total_interest_fees_amount AS interest_fee_amount,
    fine_amount,
    credit_card_fee_amount,
    ROUND(debt_amount + fine_amount + total_interest_fees_amount + credit_card_fee_amount, 2) AS total_debt_amount,
    discount_amount,
    negotiated_amount,
    down_payment_amount,
    percentage_paid_agreement/100 * negotiated_amount AS total_paid_amount,
    dt_cancellation,
    dt_promisse,
    dt_due_promisse,
    dt_expected_end AS dt_negotiation_expected_end,
    dt_down_payment,
    dt_paid_all,
    COALESCE(dt_cancellation, dt_paid_all) AS dt_ending,
    'Cyber' AS source,
    1 AS priority
  FROM datalake_cyber_homolog.negotiation
  WHERE creditor = "QuintoAndar"

  UNION DISTINCT

  SELECT
    CAST(id_negotiation AS STRING) AS id_negotiation,
    id_contract,
    UPPER(id_operator) AS id_operator,
    customer_document AS id_customer,
    campaign_code AS id_campaign,
    COUNT(id_contract) OVER(PARTITION BY id_negotiation) AS contracts_by_negotiation,
    CASE
        WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
        ELSE "IQ QuintoAndar"
    END AS creditor,
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
    IF(is_special_installment IS TRUE, "Special Installment", NULL) AS exception,
    origin_agreement,
    advisory,
    agreement_type,
    promisse_payment_method,
    down_payment AS is_down_payment_paid,
    number_of_installments,
    paid_installments,
    breached_installments,
    original_debt_amount,
    interest_fee_amount,
    IF(is_special_installment IS TRUE, fine_fee_amount, GREATEST(ROUND(expense_amount - original_debt_amount - interest_fee_amount - adm_fee_amount - negotiation_discount_amount, 2), 0))  AS fine_amount,
    adm_fee_amount AS credit_card_fee_amount,
    ROUND(expense_amount,2) AS total_debt_amount, -- original_debt_amount + interest_fee_amount + fine_fee_amount + credit_card_fee
    GREATEST(ROUND(expense_amount - negotiated_amount, 2), 0) AS discount_amount,
    negotiated_amount,
    down_payment_amount_without_fees AS down_payment_amount,
    total_amount_paid AS total_paid_amount,
    dt_cancellation,
    dt_promisse,
    dt_due_promisse,
    dt_negotiation_expected_end,
    dt_down_payment,
    dt_paid_all,
    COALESCE(dt_cancellation, dt_paid_all) AS dt_ending,
    'Recupera' AS source,
    2 AS priority
  FROM datalake_recupera.negotiation
  WHERE id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation ORDER BY ts_snapshot DESC, id_contract DESC) = 1
),
original_invoices AS (
  SELECT
    b.sk_negotiation AS id_negotiation,
    MIN(d.dt_due) AS dt_due_invoice_anchor,
    COUNT(DISTINCT d.id_invoice) AS total_invoices_negotiated
  FROM dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
  INNER JOIN dw_collection_recovery_quintoandar.fact_debt AS d
    ON d.sk_debt = b.sk_debt
  GROUP BY 1
),
installments_data AS (
  SELECT
    sk_negotiation AS id_negotiation,
    payment_method AS promisse_payment_method,
    paid_amount AS down_payment_amount,
    IF(dt_paid IS NOT NULL, TRUE, FALSE) is_down_payment_paid,
    dt_paid AS dt_down_payment
  FROM dw_collection_recovery_quintoandar.fact_negotiation_installment
  WHERE installment_number = 1
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
    COALESCE(exs.id_negotiation, tfn.id_negotiation) AS sk_negotiation,
    COALESCE(exs.id_customer, tfn.id_customer) AS sk_debtor,
    tfn.id_negotiation_trato_feito,
    COALESCE(exs.id_contract, tfn.id_contract) AS id_contract,
    exs.id_operator,
    exs.id_campaign,
    COALESCE(exs.source, tfn.source) AS source,
    COALESCE(exs.creditor, tfn.creditor) AS creditor,
    COALESCE(exs.advisory, tfn.advisory) AS advisory,
    exs.agreement_type,
    COALESCE(exs.origin_agreement, tfn.origin_agreement) AS origin_agreement,
    COALESCE(tfn.status, exs.negotiation_status) AS negotiation_status,
    CASE
      WHEN COALESCE(exs.negotiation_status,tfn.status) = "canceled" THEN "PROMESSA QUEBRADA"
      WHEN oi.total_invoices_negotiated >= 1 AND number_of_installments > 1 THEN "ACORDO"
      WHEN oi.total_invoices_negotiated > 1 AND number_of_installments = 1 THEN "QUITAÇÃO"
      WHEN oi.total_invoices_negotiated = 1 AND number_of_installments = 1 THEN "SUBSTITUIÇÃO"
      WHEN COALESCE(exs.negotiation_status, tfn.status) = "started" THEN "PROMESSA"
      ELSE "INDEFINIDO"
    END AS negotiation_classification,
    COALESCE(i.promisse_payment_method, exs.promisse_payment_method, tfn.promisse_payment_method) AS promisse_payment_method, -- add info no tf
    CASE
      WHEN exs.contracts_by_negotiation > 1 THEN TRUE
      WHEN exs.exception IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_not_standard_negotiation, -- incluir TF
    CASE
      WHEN exs.contracts_by_negotiation > 1 THEN "Multiple contracts included in negotiation"
      ELSE exs.exception
    END AS not_standard_reason, -- incluir TF
    COALESCE(i.is_down_payment_paid, exs.is_down_payment_paid, tfn.is_down_payment_paid) AS is_down_payment_paid,
    tfn.is_renegotiation, -- pegar dados de todas as fontes
    r.has_been_renegotiated, -- pegar dados de todas as fontes
    oi.total_invoices_negotiated,
    COALESCE(exs.number_of_installments, tfn.qt_installments) AS number_of_installments,
    COALESCE(exs.paid_installments, tfn.qt_installments_paid, 0) AS paid_installments,
    COALESCE(exs.breached_installments, tfn.breached_installments, 0) AS breached_installments,
    COALESCE(exs.original_debt_amount, tfn.original_debt_amount) AS original_debt_amount,
    COALESCE(exs.fine_amount, tfn.fine_amount, 0) AS fine_fee_amount,
    COALESCE(exs.interest_fee_amount, tfn.interest_fee_amount, 0) AS interest_fee_amount,
    COALESCE(exs.credit_card_fee_amount, tfn.credit_card_fee_amount, 0) AS credit_card_fee_amount,
    COALESCE(exs.total_debt_amount, tfn.total_debt_amount) AS total_debt_amount,
    COALESCE(exs.discount_amount, tfn.total_discount_amount, 0) AS total_discount_amount,
    COALESCE(exs.negotiated_amount, tfn.negotiated_amount) AS negotiated_amount,
    COALESCE(i.down_payment_amount, exs.down_payment_amount, tfn.down_payment_amount) AS down_payment_amount,
    COALESCE(tfn.paid_amount, exs.total_paid_amount, 0) AS paid_amount,
    oi.dt_due_invoice_anchor,
    COALESCE(exs.dt_promisse, tfn.dt_promisse) AS dt_promisse,
    exs.dt_due_promisse, -- pegar dado do trato feito
    COALESCE(exs.dt_cancellation, tfn.dt_breach) AS dt_cancellation,
    COALESCE(i.dt_down_payment, exs.dt_down_payment, tfn.dt_first_payment) AS dt_down_payment,
    COALESCE(exs.dt_paid_all, tfn.dt_paid_all) AS dt_paid_all_installments,
    COALESCE(exs.dt_negotiation_expected_end, tfn.dt_expected_end) AS dt_expected_ending,
    COALESCE(exs.dt_ending, tfn.dt_ending) AS dt_ending
  FROM
    union_external_sources AS exs
  FULL OUTER JOIN
      trato_feito_negotiation AS tfn
        ON exs.id_negotiation = tfn.id_negotiation
  LEFT JOIN
      renegotiation AS r
        ON tfn.id_negotiation = r.id_negotiation
  LEFT JOIN original_invoices AS oi
    ON tfn.id_negotiation = oi.id_negotiation
  LEFT JOIN installments_data AS i
    ON COALESCE(exs.id_negotiation, tfn.id_negotiation) = i.id_negotiation
)
SELECT
  u.sk_negotiation,
  u.sk_debtor,
  u.id_negotiation_trato_feito,
  CAST(u.id_contract AS BIGINT) AS id_contract,
  COALESCE(po.operator_name, u.id_operator) AS id_operator,
  u.id_campaign,
  u.creditor,
  u.is_not_standard_negotiation,
  u.not_standard_reason,
  u.agreement_type,
  u.advisory,
  u.origin_agreement,
  u.negotiation_status,
  u.negotiation_classification,
  u.promisse_payment_method,
  IF(u.is_down_payment_paid IS TRUE, "ACORDO", "PROMESSA") AS agreement_promise,
  u.is_renegotiation,
  u.has_been_renegotiated,
  CASE
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 0 THEN "Current"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 30  THEN "1-30"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 60  THEN "31-60"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 90  THEN "61-90"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 120 THEN "91-120"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) <= 180 THEN "121-180"
    WHEN DATEDIFF(u.dt_promisse, u.dt_due_invoice_anchor) IS NULL THEN NULL
    ELSE "over 180"
  END AS delay_contamined_range,
  u.total_invoices_negotiated,
  u.number_of_installments,
  u.paid_installments,
  u.breached_installments,
  u.original_debt_amount,
  u.fine_fee_amount,
  u.interest_fee_amount,
  u.credit_card_fee_amount,
  u.total_debt_amount,
  u.total_discount_amount,
  ROUND(IF(u.total_discount_amount >= (u.fine_fee_amount + u.interest_fee_amount),
    (u.fine_fee_amount + u.interest_fee_amount),
    u.total_discount_amount), 2) AS discount_to_fees_amount,
  ROUND(IF(u.total_discount_amount >= (u.fine_fee_amount + u.interest_fee_amount),
    u.total_discount_amount - (u.fine_fee_amount + u.interest_fee_amount),
    0), 2) AS discount_to_original_amount,
  u.negotiated_amount,
  u.down_payment_amount,
  IF(is_down_payment_paid IS NOT NULL, down_payment_amount, 0) AS down_payment_amount_paid,
  u.paid_amount,
  u.dt_due_invoice_anchor,
  u.dt_promisse,
  u.dt_due_promisse,
  u.dt_cancellation,
  u.dt_down_payment,
  u.dt_paid_all_installments,
  u.dt_expected_ending,
  u.dt_ending,
  NOW() AS ts_load
FROM union_sources AS u
LEFT JOIN paschoalotto_operator AS po
  ON
    UPPER(u.id_operator) LIKE "%PASCH%"
    AND po.id_contract = u.id_contract
    AND po.id_negotiation = u.sk_negotiation
    AND po.dt_promisse = u.dt_promisse
