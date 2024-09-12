WITH discounts AS (
  SELECT
    id_agreement,
    SUM(IF(field_name = "Valor dos Juros para Acordo (Visão Contrato)", amount_without_discount, 0)) AS total_fees_amount,
    SUM(IF(field_name = "Valor da Multa para Acordo (Visão Contrato)", amount_without_discount, 0)) AS total_fine_amount,
    SUM(IF(field_name = "Valor principal das parcelas vencidas selecionadas", amount_without_discount, 0)) AS total_original_amount,
    SUM(IF(field_name = "Valor principal das parcelas vencidas selecionadas", discount, 0)) AS discount_to_original_amount,
    SUM(IF(field_name = "Valor da Multa para Acordo (Visão Contrato)", discount, 0)) AS discount_to_fine_amount,
    SUM(IF(field_name = "Valor dos Juros para Acordo (Visão Contrato)", discount, 0)) AS discount_to_fees_amount,
    SUM(amount_without_discount) AS total_debt_amount,
    SUM(amount_with_discount) AS total_negotiated_amount,
    SUM(discount) AS total_discount_amount
  FROM datalake_cyber_clean.agreement_discounts
  GROUP BY 1
),
installments AS (
  SELECT
    ai.id_agreement,
    SUM(amount_to_pay) AS total_negotiated_amount,
    SUM(tax_amount) AS total_credit_card_fee_amount,
    MIN(IF(ai.installment_number = 0, DATE(ai.ts_due_installment), NULL)) AS dt_due_promisse,
    SUM(IF(ai.installment_number = 0, p.payment_amount, 0)) AS down_payment_amount,
    MAX(IF(ai.installment_number = 0, DATE(p.ts_payment), NULL)) AS dt_down_payment,
    MAX(ai.installment_number) + 1 AS total_paid_installments,
    MAX(IF(ai.installment_number = 0, p.payment_method, NULL)) AS promisse_payment_method
  FROM datalake_cyber_clean.agreement_installments AS ai
  INNER JOIN datalake_cyber_clean.payments AS p
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
    cp.offer_number AS id_campaign,
    a.contract_group AS creditor,
    a.agreement_type AS agreement_type,
    at.agreement_type_description,
    i.promisse_payment_method,
    at.min_down_payment_percentage,
    CASE
      WHEN ag.agency_type IN ("Assessoria Convencional", "Assessoria Digital") THEN "Assessoria"
      WHEN ag.agency_type = "Portal" THEN "Portal Auto Negociação"
      WHEN cp.id_campaign IS NOT NULL THEN "Carta Campanha"
      WHEN ag.agency_type = "Cyber Credit" THEN "Operador Interno"
      ELSE ag.agency_type
    END AS origin_agreement,
    a.status AS original_negotiation_status,
    CASE
        WHEN a.status = "Autorizado" THEN "offset"
        WHEN a.status = "Finalizado" THEN "finished"
        WHEN a.status = "Cancelado" THEN "canceled"
        WHEN a.status = "Pendente" THEN "started"
        ELSE a.status
    END AS negotiation_status,
    a.number_of_installments + 1 AS number_of_installments,
    i.total_paid_installments AS paid_installments,
    a.broken_payments AS breached_installments,
    d.total_original_amount,
    i.total_credit_card_fee_amount,
    d.total_fine_amount,
    d.total_fees_amount,
    d.total_debt_amount AS total_debt_amount_without_credit_card_fee,
    d.total_debt_amount + i.total_credit_card_fee_amount AS total_debt_amount_with_credit_card_fee,
    i.total_negotiated_amount,
    d.total_discount_amount,
    d.discount_to_original_amount,
    d.discount_to_fine_amount,
    d.discount_to_fees_amount,
    a.percentage_paid_agreement,
    i.down_payment_amount,
    a.ts_agreement_creation AS dt_promisse,
    i.dt_due_promisse,
    i.dt_down_payment
FROM datalake_cyber_clean.agreements AS a
INNER JOIN datalake_cyber_clean.contracts_agreements AS ca
  ON a.id_agreement = ca.id_agreement
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON ca.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.campaign As cp
  ON a.id_agreement = cp.id_negotiation
LEFT JOIN datalake_cyber_clean.users AS u
  ON a.id_user = u.id_user
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
LEFT JOIN datalake_cyber_clean.agreement_type AS at
  ON a.agreement_type = at.id_agreement_type
LEFT JOIN discounts AS d
  ON a.id_agreement = d.id_agreement
LEFT JOIN installments AS i
  ON i.id_agreement = a.id_agreement
