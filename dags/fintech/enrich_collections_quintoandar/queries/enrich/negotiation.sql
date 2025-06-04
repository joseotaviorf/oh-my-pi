WITH
trato_feito_negotiation AS (
  SELECT
    COALESCE(CAST(n.id_negotiation_external AS BIGINT), n.id_negotiation_external) AS id_negotiation,
    n.id_negotiation AS id_negotiation_trato_feito,
    n.id_contract,
    REGEXP_REPLACE(cl.document,r'\.|\-', '') AS id_customer,
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
      WHEN n.consultancy_name IN ("PASCHOALOTTO", "MEETCALL", "TRC", "GRB", "MONEST") THEN "Assessoria"
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
    agreement_type_description,
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
)
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
    cn.agreement_type_description,
    COALESCE(rn.origin_agreement, cn.origin_agreement, tfn.origin_agreement) AS origin_agreement,
    cn.campaign_status,
    cn.broken_reason,
    COALESCE(tfn.status, cn.negotiation_status, rn.negotiation_status) AS negotiation_status,
    UPPER(COALESCE(tfn.promisse_payment_method, cn.promisse_payment_method, rn.promisse_payment_method)) AS promisse_payment_method,
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
    COALESCE(tfn.down_payment_amount, cn.down_payment_amount, rn.down_payment_amount) AS down_payment_amount,
    COALESCE(tfn.paid_amount, cn.total_paid_amount, rn.total_paid_amount, 0) AS paid_amount,
    COALESCE(tfn.dt_promisse, cn.dt_promisse, rn.dt_promisse) AS dt_promisse,
    COALESCE(cn.dt_due_promisse, rn.dt_due_promisse) AS dt_due_promisse,
    COALESCE(tfn.dt_cancellation, cn.dt_cancellation, rn.dt_cancellation) AS dt_cancellation,
    COALESCE(tfn.dt_down_payment, cn.dt_down_payment, rn.dt_down_payment) AS dt_down_payment,
    COALESCE(tfn.dt_paid_all, cn.dt_paid_all, rn.dt_paid_all) AS dt_paid_all_installments,
    COALESCE(tfn.dt_expected_end, cn.dt_expected_end, rn.dt_expected_end) AS dt_expected_ending,
    NOW() AS ts_load
FROM
    trato_feito_negotiation AS tfn
FULL OUTER JOIN
    cyber_negotiation AS cn
        ON tfn.id_negotiation = cn.id_negotiation
            AND tfn.id_contract = cn.id_contract
FULL OUTER JOIN
    recupera_negotiation AS rn
    ON tfn.id_negotiation = rn.id_negotiation
        AND tfn.id_contract = rn.id_contract
