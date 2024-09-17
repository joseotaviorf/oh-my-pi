WITH
eviction_costs AS (
  SELECT
    ha.id_agreement,
    SUM(b.eviction_honorarium_amount) AS eviction_honorarium_amount
  FROM datalake_cyber_clean.historical_agreements AS ha
  LEFT JOIN datalake_cyber_clean.bill AS b
    ON b.id_invoice = ha.id_invoice
  GROUP BY 1
),
amount_details AS (
  SELECT
    ad.id_agreement,
    SUM(IF(ad.field_name IN ("Juros Residuais", "Juros Acordo"), ad.amount_without_discount, 0)) AS contract_interest_fees_amount,
    SUM(IF(ad.field_name IN ("Multa Residual", "Multa Acordo"), ad.amount_without_discount, 0)) AS fine_amount,
    SUM(IF(ad.field_name IN ("Parcelas Vencidas", "Parcelas a Vencer"), ad.amount_without_discount, 0)) AS original_amount,
    SUM(IF(ad.field_name IN ("Custas Residuais", "Custas Acordo"), ad.amount_without_discount, 0)) AS eviction_costs_amount,
    SUM(ec.eviction_honorarium_amount) AS eviction_honorarium_amount,
    SUM(IF(ad.field_name IN ("Parcelas Vencidas", "Parcelas a Vencer"), ad.discount, 0)) AS discount_to_original_amount,
    SUM(IF(ad.field_name IN ("Juros Residuais", "Juros Acordo"), ad.discount, 0)) AS discount_to_fees_amount,
    SUM(IF(ad.field_name IN ("Multa Residual", "Multa Acordo"), ad.discount, 0)) AS discount_to_fine_amount,
    SUM(IF(ad.field_name IN ("Custas Residuais", "Custas Acordo"), ad.discount, 0)) AS discount_to_eviction_costs,
    SUM(ad.amount_without_discount) AS debt_amount,
    SUM(ad.amount_with_discount) AS negotiated_amount,
    SUM(ad.discount) AS discount_amount
  FROM datalake_cyber_clean.agreement_discounts AS ad
  LEFT JOIN eviction_costs AS ec
    ON ad.id_agreement = ec.id_agreement
  GROUP BY 1
),
installments AS (
  SELECT
    ai.id_agreement,
    SUM(amount_to_pay) AS negotiated_amount,
    SUM(credit_card_fee_amount) AS credit_card_fee_amount,
    SUM(interest_amount) AS installment_interest_fees_amount,
    MIN(IF(ai.installment_number = 0, DATE(ai.ts_due_installment), NULL)) AS dt_due_promisse,
    SUM(IF(p.id_agreement_installment IS NOT NULL AND ai.installment_number = 0, p.payment_amount, 0)) AS down_payment_amount,
    MAX(IF(p.id_agreement_installment IS NOT NULL AND ai.installment_number = 0, DATE(p.ts_payment), NULL)) AS dt_down_payment,
    MAX(IF(p.id_agreement_installment IS NOT NULL, ai.installment_number + 1, 0)) AS paid_installments,
    MAX(IF(ai.installment_number = 0, p.payment_method, NULL)) AS promisse_payment_method
  FROM datalake_cyber_clean.agreement_installments AS ai
  LEFT JOIN datalake_cyber_clean.payments AS p
    ON ai.id_agreement_installment = p.id_agreement_installment
  GROUP BY 1
)
SELECT
    a.id_agreement AS id_negotiation,
    ca.id_contract,
    c.id_contract_external,
    c.id_client AS id_customer,
    a.id_user AS id_operator,
    ag.agency_name AS advisory,
    ca.contract_group AS creditor,
    a.agreement_type AS agreement_type,
    at.agreement_type_description,
    a.frequency,
    i.promisse_payment_method,
    at.min_down_payment_percentage,
    CASE
      WHEN ag.agency_type IN ("Assessoria Convencional", "Assessoria Digital") THEN "Assessoria"
      WHEN ag.agency_type = "Portal" THEN "Portal Auto Negociação"
      WHEN ag.agency_type = "Cyber Credit" THEN "Operador Interno"
      ELSE ag.agency_type
    END AS origin_agreement,
    a.status AS original_negotiation_status,
    CASE
        WHEN a.status = "Autorizado" THEN "offset"
        WHEN a.status = "Finalizado" THEN "finished"
        WHEN a.status = "Cancelado" AND i.dt_down_payment IS NOT NULL THEN "broken"
        WHEN a.status = "Cancelado" AND i.dt_down_payment IS NULL THEN "canceled"
        WHEN a.status = "Pendente" THEN "started"
        ELSE a.status
    END AS negotiation_status,
    IF(i.dt_down_payment IS NOT NULL, TRUE, FALSE) AS is_down_payment_paid,
    a.number_of_installments,
    i.paid_installments,
    IF(a.status = "Cancelado", a.number_of_installments - i.paid_installments, 0) AS breached_installments,
    d.original_amount,
    a.type_interest_quota,
    a.interest_rate,
    a.additional_interest_rate,
    d.fine_amount,
    d.contract_interest_fees_amount,
    i.installment_interest_fees_amount,
    d.contract_interest_fees_amount + i.installment_interest_fees_amount AS total_interest_fees_amount,
    d.eviction_costs_amount,
    d.eviction_honorarium_amount,
    i.credit_card_fee_amount,
    d.debt_amount + d.eviction_honorarium_amount AS debt_amount,
    d.negotiated_amount + i.credit_card_fee_amount AS negotiated_amount,
    d.discount_amount,
    d.discount_to_original_amount,
    d.discount_to_fine_amount,
    d.discount_to_fees_amount,
    d.discount_to_eviction_costs,
    ROUND(a.percentage_paid_agreement, 2) AS percentage_paid_agreement,
    i.down_payment_amount,
    a.ts_agreement_creation AS dt_promisse,
    i.dt_due_promisse,
    i.dt_down_payment
FROM datalake_cyber_clean.agreements AS a
INNER JOIN datalake_cyber_clean.contracts_agreements AS ca
  ON a.id_agreement = ca.id_agreement
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON ca.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON a.id_user = u.id_user
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
LEFT JOIN datalake_cyber_clean.agreement_type AS at
  ON a.agreement_type = at.id_agreement_type
LEFT JOIN amount_details AS d
  ON a.id_agreement = d.id_agreement
LEFT JOIN installments AS i
  ON i.id_agreement = a.id_agreement
