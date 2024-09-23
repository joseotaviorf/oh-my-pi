WITH
amount_details AS (
  SELECT
    ad.id_agreement,
    SUM(IF(ad.field_name IN ("Juros Residuais", "Juros Acordo"), ad.amount_without_discount, 0)) AS contract_interest_fees_amount,
    SUM(IF(ad.field_name IN ("Multa Residual", "Multa Acordo"), ad.amount_without_discount, 0)) AS fine_amount,
    SUM(IF(ad.field_name IN ("Parcelas Vencidas", "Parcelas a Vencer"), ad.amount_without_discount, 0)) AS original_amount,
    SUM(IF(ad.field_name IN ("Custas Residuais", "Custas Acordo"), ad.amount_without_discount, 0)) AS eviction_costs_amount,
    SUM(ad.discount) AS discount_amount
  FROM datalake_cyber_clean.agreement_discounts AS ad
  GROUP BY 1
),
total_installments AS (
  SELECT
    id_agreement,
    MAX(installment_number) + 1 AS total_installments
  FROM datalake_cyber_clean.agreement_installments
  GROUP BY 1
),
split_fees_between_installments AS (
    SELECT
      a.id_agreement,
      i.total_installments,
      a.contract_interest_fees_amount,
      floor(a.contract_interest_fees_amount/i.total_installments,2) AS contract_interest,
      a.contract_interest_fees_amount - floor(a.contract_interest_fees_amount/i.total_installments,2) * (i.total_installments - 1) AS last_contract_interest,
      floor(a.fine_amount/i.total_installments,2) AS installment_fee,
      a.fine_amount - floor(a.fine_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_fee,
      floor(a.eviction_costs_amount/i.total_installments,2) AS installment_costs,
      a.eviction_costs_amount - floor(a.eviction_costs_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_costs,
      floor(a.discount_amount/i.total_installments,2) AS installment_discount,
      a.discount_amount - floor(a.discount_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_discount
    FROM amount_details AS a
    INNER JOIN total_installments AS i
      ON  a.id_agreement = i.id_agreement
  ),
  calculate_fields AS (
    SELECT
      ai.id_agreement_installment,
      ai.id_agreement AS id_negotiation,
      ca.id_contract,
      c.id_contract_external,
      c.id_client AS id_debtor,
      p.id_payment AS id_receipt,
      ain.our_number,
      ai.installment_number + 1 AS installment_number,
      ca.contract_group AS creditor,
      ai.status,
      CASE
          WHEN ai.status = 'Quebrado' THEN 'canceled'
          WHEN ai.status = 'Concluído' THEN 'paid'
          WHEN ai.status IN ('Pendente de Pagamento', 'Programado') THEN 'pending'
          ELSE ai.status
      END AS installment_status,
      p.payment_type,
      p.payment_method,
      ain.has_sent_boleto,
      at.fine_rate,
      ai.amortization_amount,
      ai.installment_interest_amount,
      ai.credit_card_fee_amount,
      CASE
        WHEN ai.installment_number + 1 = f.total_installments THEN f.last_contract_interest
        ELSE f.contract_interest
      END AS contract_interest_amount,
      CASE
        WHEN ai.installment_number + 1 = f.total_installments THEN f.last_installment_fee
        ELSE f.installment_fee
      END AS fine_amount,
      CASE
        WHEN ai.installment_number + 1 = f.total_installments THEN f.last_installment_costs
        ELSE f.installment_costs
      END AS eviction_costs_amount,
      ai.honorarium_amount,
      CASE
        WHEN ai.installment_number + 1 = f.total_installments THEN f.last_installment_discount
        ELSE f.installment_discount
      END AS discount_amount,
      ai.amount_to_pay,
      ai.agreement_balance_amount,
      p.payment_amount AS paid_amount,
      DATE(a.ts_agreement_creation) AS dt_creation,
      DATE(ai.ts_due_installment) AS dt_due,
      DATE(p.ts_payment) AS dt_paid,
      DATE(ain.ts_document) AS dt_emission_boleto,
      DATE(ain.ts_due) AS dt_due_boleto,
      DATE(ain.ts_processing) AS dt_processing_boleto
    FROM datalake_cyber_clean.agreement_installments AS ai
    LEFT JOIN datalake_cyber_clean.agreements AS a
        ON ai.id_agreement = a.id_agreement
    INNER JOIN datalake_cyber_clean.contracts_agreements AS ca
      ON ai.id_agreement = ca.id_agreement
    INNER JOIN datalake_cyber_clean.contracts AS c
      ON ca.id_contract = c.id_contract
    LEFT JOIN datalake_cyber_clean.payments AS p
      ON ai.id_agreement_installment = p.id_agreement_installment
    LEFT JOIN datalake_cyber_clean.agreement_invoices AS ain
      ON ai.id_agreement = ain.id_agreement
        AND ai.installment_number = ain.installment_number
    LEFT JOIN datalake_cyber_clean.agreement_type AS at
      ON a.agreement_type = at.id_agreement_type
    LEFT JOIN split_fees_between_installments AS f
      ON ai.id_agreement = f.id_agreement
  )
  SELECT
    id_agreement_installment,
    id_negotiation,
    id_contract,
    id_contract_external,
    id_debtor,
    id_receipt,
    our_number,
    installment_number,
    creditor,
    status,
    installment_status,
    payment_type,
    payment_method,
    amount_to_pay - credit_card_fee_amount - installment_interest_amount - contract_interest_amount - fine_amount - eviction_costs_amount - honorarium_amount  + discount_amount AS original_amount,
    amortization_amount, -- = amount_to_pay - credit_card_fee_amount
    fine_rate,
    fine_amount,
    contract_interest_amount,
    installment_interest_amount,
    installment_interest_amount + contract_interest_amount AS total_interest_amount,
    credit_card_fee_amount,
    eviction_costs_amount,
    honorarium_amount,
    eviction_lawyers_fee_amount,
    discount_amount,
    amount_to_pay,
    agreement_balance_amount,
    paid_amount,
    dt_creation,
    dt_due,
    dt_paid,
    NOW() AS ts_load
  FROM calculate_fields
