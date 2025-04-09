WITH
trato_feito_negotiation AS (
  SELECT
    COALESCE(CAST(n.id_negotiation_external AS BIGINT), n.id_negotiation_external) AS id_negotiation,
    n.id_negotiation AS id_negotiation_trato_feito,
    n.id_contract,
    REGEXP_REPLACE(cl.document,r"\.|\-", "") AS id_customer,
    CASE
      WHEN LOWER(n.collector) LIKE "%cyber%" AND BIGINT(n.id_negotiation_external) < 10000000 THEN "Trato Feito - Cyber (Migração)"
      WHEN LOWER(n.collector) LIKE "%cyber%" AND BIGINT(n.id_negotiation_external) >= 10000000 THEN "Trato Feito - Cyber"
      WHEN LOWER(n.collector) LIKE "%recupera%" THEN "Trato Feito - Recupera"
      WHEN UPPER(n.collector) LIKE "%5A%" THEN "Trato Feito - Self Service"
    END AS source,
    COUNT(n.id_contract) OVER(PARTITION BY n.id_negotiation_external) AS contracts_by_negotiation,
    CASE
      WHEN n.debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN n.debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
    n.consultancy_name AS advisory,
    CASE
      WHEN n.consultancy_name = "PORTAL_QUINTOANDAR" THEN "Portal Auto Negociação"
      WHEN n.consultancy_name IN ("PASCHOALOTTO", "MEETCALL", "TRC", "GRB") THEN "Assessoria"
      WHEN n.consultancy_name = "SERASA" THEN "Serasa Digital"
      WHEN n.consultancy_name = "COBRANÇA_INTERNA_QA" THEN "Operador Interno"
    END AS origin_agreement,
    n.promisse_payment_method,
    n.status,
    n.has_renegotiated AS is_renegotiation,
    n.qt_installments AS number_of_installments,
    n.negotiation_original_amount AS original_debt_amount,
    n.interest_fee_amount,
    n.fine_fee_amount AS fine_amount,
    n.credit_card_fee_amount,
    n.installment_costs AS installment_eviction_costs,
    n.installment_lawyers_fee,
    n.negotiation_original_amount + n.fine_fee_amount + n.interest_fee_amount + n.installment_costs + n.installment_lawyers_fee AS total_debt_amount,
    n.negotiation_discount_amount AS discount_amount, -- Total debt (total_debt_amount = original + fine + fee + credit card) - Negotiated amount (total_expected_amount)
    n.total_expected_amount AS negotiated_amount,
    n.down_payment_amount,
    n.paid_amount,
    INT(n.qt_installments_paid) AS paid_installments,
    IF(n.breached_installment IS NOT NULL, INT(n.qt_installments) - INT(n.qt_installments_paid), 0) AS breached_installments,
    n.dt_expected_end,
    DATE(n.ts_created_at) AS dt_promisse,
    DATE(n.ts_first_payment) AS dt_down_payment,
    DATE(n.ts_paid_all) AS dt_paid_all,
    DATE(n.ts_breach) AS dt_cancellation,
    DATE(COALESCE(n.ts_breach, n.ts_paid_all)) AS dt_ending
  FROM datalake_debt_recovery.negotiation AS n
  LEFT JOIN datalake_trato_feito_clean.contract AS ct
    ON n.id_contract = ct.id_external
  LEFT JOIN datalake_trato_feito_clean.client AS cl
    ON cl.id_contract = ct.id AND cl.client_type = "main-tenant"
  WHERE n.debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY n.id_contract, n.id_negotiation_external ORDER BY n.ts_created_at DESC, cl.ts_created DESC) = 1 -- removes the exception in which 1 Trato-Feito negotiation ID has more than one Recupera negotiation ID. Ex: 97080, and when 1 contract has more then 1 main-tenant living in the house.
),
cyber_negotiation AS (
  SELECT
    CAST(id_negotiation AS BIGINT) AS id_negotiation,
    id_contract,
    id_operator,
    id_user_authorized AS id_manager_authorized,
    id_customer,
    id_campaign,
    COUNT(id_contract) OVER(PARTITION BY id_negotiation) AS contracts_by_negotiation,
    "IQ QuintoAndar" AS creditor,
    campaign_status,
    description_broken_agreement AS broken_reason,
    negotiation_status,
    exception,
    origin_agreement,
    advisory,
    agreement_type,
    promisse_payment_method,
    payment_method,
    NULL AS is_renegotiation,
    number_of_installments,
    paid_installments,
    breached_installments,
    original_amount AS original_debt_amount,
    total_interest_fees_amount AS interest_fee_amount,
    fine_amount,
    credit_card_fee_amount,
    eviction_costs_amount AS installment_eviction_costs,
    honorarium_amount AS installment_lawyers_fee,
    debt_amount AS total_debt_amount,
    discount_amount,
    discount_to_original_amount,
    discount_to_fees_amount + discount_to_fine_amount + discount_to_eviction_costs AS discount_to_fees_amount,
    CASE
      WHEN discount_amount > discount_to_original_amount + discount_to_fees_amount + discount_to_fine_amount + discount_to_eviction_costs
       THEN discount_amount - (discount_to_original_amount + discount_to_fees_amount + discount_to_fine_amount + discount_to_eviction_costs)
      ELSE 0
    END AS discount_to_credit_fee_amount,
    negotiated_amount,
    down_payment_amount,
    percentage_paid_agreement/100 * negotiated_amount AS total_paid_amount,
    dt_cancellation,
    dt_promisse,
    dt_due_promisse,
    dt_expected_end,
    dt_down_payment,
    dt_paid_all,
    COALESCE(dt_cancellation, dt_paid_all) AS dt_ending,
    "Cyber" AS source,
    1 AS priority
  FROM datalake_cyber.negotiation
  WHERE creditor = "QuintoAndar"
),
recupera_negotiation AS (
  SELECT
    CAST(rn.id_negotiation AS BIGINT) AS id_negotiation,
    COALESCE(n.id_contract, rn.id_contract) AS id_contract,
    UPPER(rn.id_operator) AS id_operator,
    rn.customer_document AS id_customer,
    rn.campaign_code AS id_campaign,
    COUNT(rn.id_contract) OVER(PARTITION BY rn.id_negotiation) AS contracts_by_negotiation,
    CASE
        WHEN rn.id_creditor IN (2,6) THEN "PP QuintoAndar"
        ELSE "IQ QuintoAndar"
    END AS creditor,
    CASE
      WHEN rn.negotiation_status = "ACORDO_LIQUIDADO" THEN "finished"
      WHEN rn.negotiation_status = "ACORDO_CANCELADO"
        AND rn.down_payment IS TRUE THEN "broken"
      WHEN rn.negotiation_status = "ACORDO_CANCELADO"
        AND rn.down_payment IS FALSE THEN "canceled"
      WHEN rn.negotiation_status = "ACORDO_EM_ANDAMENTO"
        AND rn.down_payment IS TRUE THEN "offset"
      WHEN rn.negotiation_status = "ACORDO_EM_ANDAMENTO" THEN "started"
    END AS negotiation_status,
    IF(rn.is_special_installment IS TRUE, "Special Installment", NULL) AS exception,
    CASE
      WHEN REPLACE(rn.origin_agreement, "_", " ") = "Portal Autonegociação" THEN "Portal Auto Negociação"
      WHEN REPLACE(rn.origin_agreement, "_", " ") =  "Operador" THEN "Operador Interno"
      WHEN REPLACE(rn.origin_agreement, "_", " ") =  "Carta Campanha" THEN "Boletagem"
      ELSE REPLACE(rn.origin_agreement, "_", " ")
    END AS origin_agreement,
    rn.advisory,
    rn.agreement_type,
    rn.promisse_payment_method,
    NULL AS is_renegotiation,
    rn.number_of_installments,
    rn.paid_installments,
    rn.breached_installments,
    rn.original_debt_amount,
    rn.interest_fee_amount,
    IF(rn.is_special_installment IS TRUE, rn.fine_fee_amount, GREATEST(rn.expense_amount - rn.original_debt_amount - rn.interest_fee_amount - rn.adm_fee_amount - rn.negotiation_discount_amount, 0))  AS fine_amount,
    rn.adm_fee_amount AS credit_card_fee_amount,
    rn.expense_amount AS total_debt_amount, -- original_debt_amount + interest_fee_amount + fine_fee_amount + credit_card_fee
    GREATEST(rn.expense_amount - rn.negotiated_amount, 0) AS discount_amount,
    rn.negotiated_amount,
    rn.down_payment_amount,
    rn.total_amount_paid AS total_paid_amount,
    rn.dt_cancellation,
    rn.dt_promisse,
    rn.dt_due_promisse,
    rn.dt_negotiation_expected_end AS dt_expected_end,
    rn.dt_down_payment,
    rn.dt_paid_all,
    COALESCE(rn.dt_cancellation, rn.dt_paid_all) AS dt_ending,
    "Recupera" AS source,
    2 AS priority
  FROM datalake_recupera.negotiation AS rn
  LEFT JOIN trato_feito_negotiation AS n
    ON CAST(rn.id_negotiation AS BIGINT) = n.id_negotiation AND n.source = "Trato Feito - Recupera"
  WHERE id_creditor NOT IN (3,5)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY rn.id_negotiation ORDER BY rn.ts_snapshot DESC, rn.id_contract DESC) = 1
),
original_invoices AS (
  SELECT
    b.sk_negotiation,
    d.id_contract,
    MIN(d.dt_due) AS dt_due_invoice_anchor,
    COUNT(DISTINCT d.id_invoice) AS total_invoices_negotiated
  FROM dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
  INNER JOIN dw_collection_recovery_quintoandar.fact_debt AS d
    ON d.sk_debt = b.sk_debt
  GROUP BY 1,2
),
installments_data AS (
  SELECT
    id_negotiation,
    sk_contract,
    payment_method AS promisse_payment_method,
    main_amount AS down_payment_original_amount,
    amount_to_pay AS down_payment_amount,
    net_amount AS down_payment_net_amount,
    dt_paid AS dt_down_payment
  FROM dw_collection_recovery_quintoandar.fact_negotiation_installment
  WHERE installment_number = 1
),
renegotiation AS (
  SELECT
    CAST(i.id_negotiation AS BIGINT) AS id_negotiation,
    i.id_contract,
    IF(COUNT(DISTINCT d.id_negotiation) > 0, TRUE, FALSE) AS has_been_renegotiated
  FROM datalake_debt_recovery.installment AS i
  LEFT JOIN datalake_trato_feito_clean.accounting_installment AS ai
    ON ai.id_installment = i.id
  LEFT JOIN datalake_trato_feito_clean.debt AS d
    ON ai.id_external = d.id_external
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
  SELECT DISTINCT
    COALESCE(tfn.id_negotiation, cn.id_negotiation, rn.id_negotiation) AS id_negotiation,
    COALESCE(tfn.id_customer, cn.id_customer, rn.id_customer) AS id_debtor,
    tfn.id_negotiation_trato_feito,
    COALESCE(tfn.id_contract, cn.id_contract, rn.id_contract) AS id_contract,
    COALESCE(rn.id_operator, cn.id_operator) AS id_operator,
    cn.id_manager_authorized,
    COALESCE(rn.id_campaign, cn.id_campaign) AS id_campaign,
    CONCAT_WS(" | ", tfn.source, cn.source, rn.source) AS source,
    COALESCE(tfn.creditor, cn.creditor, rn.creditor) AS creditor,
    COALESCE(rn.advisory, cn.advisory, tfn.advisory) AS advisory,
    COALESCE(rn.agreement_type, cn.agreement_type) AS agreement_type,
    COALESCE(rn.origin_agreement, cn.origin_agreement, tfn.origin_agreement) AS origin_agreement,
    cn.campaign_status,
    cn.broken_reason,
    COALESCE(tfn.status, cn.negotiation_status, rn.negotiation_status) AS negotiation_status,
    UPPER(COALESCE(i.promisse_payment_method, tfn.promisse_payment_method, cn.promisse_payment_method, rn.promisse_payment_method)) AS promisse_payment_method,
    cn.payment_method,
    CASE
      WHEN COALESCE(tfn.contracts_by_negotiation, cn.contracts_by_negotiation, rn.contracts_by_negotiation) > 1 THEN TRUE
      WHEN COALESCE(cn.exception, rn.exception) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_not_standard_negotiation,
    CASE
      WHEN COALESCE(tfn.contracts_by_negotiation, cn.contracts_by_negotiation, rn.contracts_by_negotiation) > 1 THEN "Multiple contracts included in negotiation"
      ELSE COALESCE(cn.exception, rn.exception)
    END AS not_standard_reason,
    COALESCE(tfn.is_renegotiation, cn.is_renegotiation, rn.is_renegotiation) AS is_renegotiation,
    r.has_been_renegotiated,
    oi.total_invoices_negotiated,
    COALESCE(tfn.number_of_installments, cn.number_of_installments, rn.number_of_installments) AS number_of_installments,
    COALESCE(tfn.paid_installments, cn.paid_installments, rn.paid_installments, 0) AS paid_installments,
    COALESCE(tfn.breached_installments, cn.breached_installments, rn.breached_installments, 0) AS breached_installments,
    COALESCE(tfn.original_debt_amount, cn.original_debt_amount, rn.original_debt_amount) AS original_debt_amount,
    COALESCE(tfn.fine_amount, cn.fine_amount, rn.fine_amount, 0) AS fine_fee_amount,
    COALESCE(tfn.interest_fee_amount, cn.interest_fee_amount, rn.interest_fee_amount, 0) AS interest_fee_amount,
    COALESCE(tfn.credit_card_fee_amount, cn.credit_card_fee_amount, rn.credit_card_fee_amount, 0) AS credit_card_fee_amount,
    COALESCE(tfn.installment_eviction_costs, cn.installment_eviction_costs, 0) AS installment_eviction_costs,
    COALESCE(tfn.installment_lawyers_fee, cn.installment_lawyers_fee, 0) AS installment_lawyers_fee,
    COALESCE(tfn.total_debt_amount, cn.total_debt_amount, rn.total_debt_amount) AS total_debt_amount,
    COALESCE(tfn.discount_amount, cn.discount_amount, rn.discount_amount, 0) AS total_discount_amount,
    cn.discount_to_original_amount,
    cn.discount_to_fees_amount,
    cn.discount_to_credit_fee_amount,
    COALESCE(tfn.negotiated_amount, cn.negotiated_amount, rn.negotiated_amount) AS negotiated_amount,
    i.down_payment_original_amount,
    COALESCE(i.down_payment_amount, tfn.down_payment_amount, cn.down_payment_amount, rn.down_payment_amount) AS down_payment_amount,
    i.down_payment_net_amount,
    COALESCE(tfn.paid_amount, cn.total_paid_amount, rn.total_paid_amount, 0) AS paid_amount,
    oi.dt_due_invoice_anchor,
    COALESCE(tfn.dt_promisse, cn.dt_promisse, rn.dt_promisse) AS dt_promisse,
    COALESCE(cn.dt_due_promisse, rn.dt_due_promisse) AS dt_due_promisse, -- pegar dado do trato feito
    COALESCE(tfn.dt_cancellation, cn.dt_cancellation, rn.dt_cancellation) AS dt_cancellation,
    COALESCE(i.dt_down_payment, tfn.dt_down_payment, cn.dt_down_payment, rn.dt_down_payment) AS dt_down_payment,
    COALESCE(tfn.dt_paid_all, cn.dt_paid_all, rn.dt_paid_all) AS dt_paid_all_installments,
    COALESCE(tfn.dt_expected_end, cn.dt_expected_end, rn.dt_expected_end) AS dt_expected_ending,
    COALESCE(tfn.dt_ending, cn.dt_ending) AS dt_ending
  FROM trato_feito_negotiation AS tfn
  FULL OUTER JOIN cyber_negotiation AS cn
    ON tfn.id_negotiation = cn.id_negotiation
      AND tfn.id_contract = cn.id_contract
  FULL OUTER JOIN recupera_negotiation AS rn
    ON tfn.id_negotiation = rn.id_negotiation
      AND tfn.id_contract = rn.id_contract
  LEFT JOIN renegotiation AS r
    ON tfn.id_negotiation = r.id_negotiation
      AND tfn.id_negotiation = r.id_contract
  LEFT JOIN original_invoices AS oi
    ON oi.sk_negotiation = CONCAT(COALESCE(tfn.id_contract, cn.id_contract, rn.id_contract),COALESCE(tfn.id_negotiation, cn.id_negotiation, rn.id_negotiation))
  LEFT JOIN installments_data AS i
    ON COALESCE(tfn.id_negotiation, cn.id_negotiation, rn.id_negotiation) = i.id_negotiation
    AND COALESCE(tfn.id_contract, cn.id_contract, rn.id_contract) = sk_contract
),
calculations AS (
  SELECT
    CONCAT(COALESCE(CAST(u.id_contract AS BIGINT), 0), CAST(u.id_negotiation AS STRING)) AS sk_negotiation,
    CAST(u.id_contract AS BIGINT) AS sk_contract,
    u.id_debtor AS sk_debtor,
    CAST(u.id_negotiation AS STRING) AS id_negotiation,
    u.id_negotiation_trato_feito,
    COALESCE(po.operator_name, u.id_operator) AS id_operator,
    u.id_manager_authorized,
    u.id_campaign,
    u.creditor,
    u.source,
    u.is_not_standard_negotiation,
    u.not_standard_reason,
    u.agreement_type,
    u.advisory,
    u.origin_agreement,
    u.campaign_status,
    u.broken_reason,
    u.negotiation_status,
    CASE
        WHEN u.dt_down_payment IS NULL
          AND u.negotiation_status = "started" THEN "PROMESSA"
        WHEN u.dt_down_payment IS NULL
          AND u.negotiation_status = "canceled" THEN "PROMESSA QUEBRADA"
        WHEN u.dt_down_payment IS NOT NULL
          AND u.total_invoices_negotiated >= 1 AND u.number_of_installments > 1 THEN "ACORDO"
        WHEN u.dt_down_payment IS NOT NULL
          AND u.total_invoices_negotiated > 1 AND u.number_of_installments = 1 THEN "QUITAÇÃO"
        WHEN u.dt_down_payment IS NOT NULL
          AND u.total_invoices_negotiated = 1 AND u.number_of_installments = 1 THEN "SUBSTITUIÇÃO"
      END AS negotiation_classification,
    CASE
      WHEN UPPER(u.promisse_payment_method) IN ("CREDIT-CARD", "CARTÃO", "CARTÃO DE CRÉDITO") THEN "CARTÃO DE CRÉDITO"
      ELSE UPPER(u.promisse_payment_method)
    END AS promisse_payment_method,
    u.payment_method,
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
    u.installment_eviction_costs,
    u.installment_lawyers_fee,
    u.total_debt_amount,
    CASE
      WHEN u.total_discount_amount = 0
         AND LOWER(source) NOT IN ("Trato Feito - Cyber", "Cyber")
         AND u.negotiated_amount < u.total_debt_amount
        THEN u.total_debt_amount - u.negotiated_amount
      ELSE u.total_discount_amount
    END AS total_discount_amount,
    u.discount_to_original_amount,
    u.discount_to_fees_amount,
    u.discount_to_credit_fee_amount,
    u.negotiated_amount,
    u.down_payment_original_amount,
    u.down_payment_amount,
    u.down_payment_net_amount,
    IF(u.dt_down_payment IS NOT NULL, u.down_payment_net_amount, 0) AS down_payment_net_amount_paid,
    u.paid_amount,
    u.dt_due_invoice_anchor,
    u.dt_promisse,
    u.dt_due_promisse,
    u.dt_cancellation,
    u.dt_down_payment,
    u.dt_paid_all_installments,
    u.dt_expected_ending,
    u.dt_ending
  FROM union_sources AS u
  LEFT JOIN paschoalotto_operator AS po
    ON
      UPPER(u.id_operator) LIKE "%PASCH%"
      AND po.id_contract = u.id_contract
      AND po.id_negotiation = u.id_negotiation
      AND po.dt_promisse = u.dt_promisse
),
calculate_discounts AS (
  SELECT
    sk_negotiation,
    sk_contract,
    sk_debtor,
    id_negotiation,
    id_negotiation_trato_feito,
    id_operator,
    id_manager_authorized,
    id_campaign,
    creditor,
    source,
    is_not_standard_negotiation,
    not_standard_reason,
    agreement_type,
    advisory,
    origin_agreement,
    campaign_status,
    broken_reason,
    negotiation_status,
    negotiation_classification,
    promisse_payment_method,
    payment_method,
    is_renegotiation,
    has_been_renegotiated,
    delay_contamined_range,
    total_invoices_negotiated,
    number_of_installments,
    paid_installments,
    breached_installments,
    original_debt_amount,
    fine_fee_amount,
    interest_fee_amount,
    credit_card_fee_amount,
    installment_eviction_costs,
    installment_lawyers_fee,
    total_debt_amount,
    total_discount_amount,
    COALESCE(discount_to_fees_amount,
      CASE
        WHEN total_discount_amount >= (fine_fee_amount + interest_fee_amount)
          THEN (fine_fee_amount + interest_fee_amount)
        ELSE total_discount_amount
      END) AS discount_to_fees_amount,
    COALESCE(discount_to_credit_fee_amount,
      CASE
        WHEN credit_card_fee_amount != 0 AND total_discount_amount = (fine_fee_amount + interest_fee_amount + credit_card_fee_amount) THEN credit_card_fee_amount
        ELSE 0
      END) AS discount_to_credit_fee_amount,
    COALESCE(discount_to_original_amount,
      CASE
        WHEN credit_card_fee_amount != 0 AND total_discount_amount = (fine_fee_amount + interest_fee_amount + credit_card_fee_amount) THEN total_discount_amount - (fine_fee_amount + interest_fee_amount + credit_card_fee_amount)
        WHEN total_discount_amount >= (fine_fee_amount + interest_fee_amount) THEN total_discount_amount - (fine_fee_amount + interest_fee_amount)
        ELSE 0
      END) AS discount_to_original_amount,
    negotiated_amount,
    down_payment_original_amount,
    down_payment_amount,
    down_payment_net_amount,
    down_payment_net_amount_paid,
    paid_amount,
    dt_due_invoice_anchor,
    dt_promisse,
    dt_due_promisse,
    dt_cancellation,
    dt_down_payment,
    dt_paid_all_installments,
    dt_expected_ending,
    dt_ending
  FROM calculations
)
SELECT
  sk_negotiation,
  sk_contract,
  sk_debtor,
  id_negotiation,
  id_negotiation_trato_feito,
  id_operator,
  id_manager_authorized,
  id_campaign,
  creditor,
  source,
  is_not_standard_negotiation,
  not_standard_reason,
  agreement_type,
  advisory,
  origin_agreement,
  campaign_status,
  broken_reason,
  negotiation_status,
  negotiation_classification,
  promisse_payment_method,
  payment_method,
  is_renegotiation,
  has_been_renegotiated,
  delay_contamined_range,
  total_invoices_negotiated,
  number_of_installments,
  paid_installments,
  breached_installments,
  CAST(original_debt_amount AS DECIMAL(14,2)) AS original_debt_amount,
  CAST(fine_fee_amount AS DECIMAL(14,2)) AS fine_fee_amount,
  CAST(interest_fee_amount AS DECIMAL(14,2)) AS interest_fee_amount,
  CAST(credit_card_fee_amount AS DECIMAL(14,2)) AS credit_card_fee_amount,
  CAST(installment_eviction_costs AS DECIMAL(14,2)) AS installment_eviction_costs,
  CAST(installment_lawyers_fee AS DECIMAL(14,2)) AS installment_lawyers_fee,
  CAST(total_debt_amount AS DECIMAL(14,2)) AS total_debt_amount,
  CAST(total_discount_amount AS DECIMAL(14,2)) AS total_discount_amount,
  CAST(discount_to_fees_amount AS DECIMAL(14,2)) AS discount_to_fees_amount,
  CAST(discount_to_credit_fee_amount AS DECIMAL(14,2)) AS discount_to_credit_fee_amount,
  CAST(discount_to_original_amount AS DECIMAL(14,2)) AS discount_to_original_amount,
  CAST(negotiated_amount AS DECIMAL(14,2)) AS negotiated_amount,
  CAST(down_payment_original_amount AS DECIMAL(14,2)) AS down_payment_original_amount,
  CAST(down_payment_amount AS DECIMAL(14,2)) AS down_payment_amount,
  CAST(CASE
    WHEN number_of_installments = 1
        THEN original_debt_amount - discount_to_original_amount
    ELSE down_payment_net_amount
  END AS DECIMAL(14,2)) AS down_payment_net_amount,
  CAST(CASE
    WHEN number_of_installments = 1
      AND dt_down_payment IS NOT NULL
        THEN original_debt_amount - discount_to_original_amount
    ELSE down_payment_net_amount_paid
  END AS DECIMAL(14,2)) AS down_payment_net_amount_paid,
  CAST(CASE
    WHEN (promisse_payment_method = "CARTÃO DE CRÉDITO" OR number_of_installments = 1)
      AND dt_down_payment IS NOT NULL
        THEN original_debt_amount - discount_to_original_amount
    WHEN promisse_payment_method != "CARTÃO DE CRÉDITO"
      AND number_of_installments != 1
      AND down_payment_net_amount_paid != 0
        THEN down_payment_net_amount_paid
    ELSE 0
  END AS DECIMAL(14,2)) AS net_paid_amount,
  CAST(paid_amount AS DECIMAL(14,2)) AS paid_amount,
  dt_due_invoice_anchor,
  dt_promisse,
  dt_due_promisse,
  dt_cancellation,
  dt_down_payment,
  dt_paid_all_installments,
  dt_expected_ending,
  dt_ending,
  NOW() AS ts_load
FROM calculate_discounts
