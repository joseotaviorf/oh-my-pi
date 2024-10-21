WITH
amount_details AS (
  SELECT
    ad.id_agreement,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Juros Residuais", "Juros Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS contract_interest_fees_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Multa Residual", "Multa Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS fine_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Parcelas Vencidas", "Parcelas a Vencer"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS original_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Custas Residuais", "Custas Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS eviction_costs_amount,
    SUM(COALESCE(ad.discount, ad.discount)) AS discount_amount
  FROM datalake_cyber_clean.agreement_discounts AS ad
  FULL OUTER JOIN datalake_cyber_clean.campaign_discounts AS cd
    ON ad.id_agreement = cd.id_offer
  GROUP BY 1
),
total_installments AS (
  SELECT
    COALESCE(ai.id_agreement, ci.id_offer) AS id_agreement,
    MAX(COALESCE(ai.installment_number, ci.installment_number)) + 1 AS total_installments
  FROM datalake_cyber_clean.agreement_installments AS ai
  FULL OUTER JOIN datalake_cyber_clean.campaign_installments AS ci
    ON ai.id_agreement = ci.id_offer AND ai.installment_number = ci.installment_number
  GROUP BY 1
),
split_fees_between_installments AS (
    SELECT
      a.id_agreement,
      i.total_installments,
      a.contract_interest_fees_amount,
      FLOOR(a.contract_interest_fees_amount/i.total_installments,2) AS contract_interest,
      a.contract_interest_fees_amount - FLOOR(a.contract_interest_fees_amount/i.total_installments,2) * (i.total_installments - 1) AS last_contract_interest,
      FLOOR(a.fine_amount/i.total_installments,2) AS installment_fee,
      a.fine_amount - FLOOR(a.fine_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_fee,
      FLOOR(a.eviction_costs_amount/i.total_installments,2) AS installment_costs,
      a.eviction_costs_amount - FLOOR(a.eviction_costs_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_costs,
      FLOOR(a.discount_amount/i.total_installments,2) AS installment_discount,
      a.discount_amount - FLOOR(a.discount_amount/i.total_installments,2) * (i.total_installments - 1) AS last_installment_discount
    FROM amount_details AS a
    INNER JOIN total_installments AS i
      ON  a.id_agreement = i.id_agreement
  ),
  union_promisses_agreements_installments AS (
    SELECT
      COALESCE(ai.id_agreement_installment, ci.id_agreement_installment) AS id_agreement_installment,
      COALESCE(ai.id_agreement, ci.id_offer) AS id_agreement,
      COALESCE(ca.id_contract, c.id_contract) AS id_contract,
      COALESCE(a.id_client, ci.id_client, c.id_contract) AS id_client,
      COALESCE(ai.installment_number, ci.installment_number) + 1 AS installment_number,
      COALESCE(ca.creditor, c.creditor) AS creditor,
      CASE
        WHEN ai.status IS NOT NULL THEN ai.status
        WHEN c.campaign_status = "Vencida" THEN "canceled"
      END AS status,
      COALESCE(a.agreement_type, c.agreement_type) AS agreement_type,
      ai.amortization_amount,
      COALESCE(ai.installment_interest_amount, ci.installment_interest_amount) AS installment_interest_amount,
      ai.credit_card_fee_amount,
      COALESCE(ai.honorarium_amount, ci.installment_honorarium_amount) AS honorarium_amount,
      COALESCE(ai.amount_to_pay, ci.installment_amount) AS amount_to_pay,
      ai.agreement_balance_amount,
      DATE(COALESCE(a.ts_agreement_creation, c.ts_boletagem_sent)) AS dt_creation,
      DATE(COALESCE(ai.ts_due_installment, ci.ts_due_installment)) AS dt_due,
      DATE(c.ts_boletagem_sent) AS dt_emission_boleto,
      DATE(c.ts_due_boletagem) AS dt_due_boleto,
      DATE(c.ts_boletagem_sent) AS dt_processing_boleto,
      CASE
        WHEN ai.status = "Quebrado" THEN DATE(ai.ts_due_installment)
        WHEN c.campaign_status = "Vencida" THEN DATE(c.ts_due_boletagem)
        ELSE NULL
      END AS dt_cancelation
    FROM datalake_cyber_clean.agreement_installments AS ai
    LEFT JOIN datalake_cyber_clean.agreements AS a
        ON ai.id_agreement = a.id_agreement
    LEFT JOIN datalake_cyber_clean.contracts_agreements AS ca
      ON ai.id_agreement = ca.id_agreement
    FULL OUTER JOIN datalake_cyber_clean.campaign_installments AS ci
      ON a.id_agreement = ci.id_offer
    LEFT JOIN datalake_cyber_clean.campaign AS c
      ON c.id_offer = ci.id_offer
  ),
  calculate_fields AS (
    SELECT
      ai.id_agreement_installment,
      ai.id_agreement AS id_negotiation,
      ai.id_contract,
      c.id_contract_external,
      COALESCE(c.id_client, ai.id_client) AS id_debtor,
      p.id_payment AS id_receipt,
      ain.our_number,
      ai.installment_number,
      COALESCE(c.creditor, ai.creditor) AS creditor,
      ai.status,
      CASE
          WHEN ai.status = "Quebrado" THEN "canceled"
          WHEN ai.status = "Concluído" THEN "paid"
          WHEN ai.status IN ("Pendente de Pagamento", "Programado") THEN "pending"
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
      ai.dt_creation,
      ai.dt_due,
      DATE(p.ts_payment) AS dt_paid,
      COALESCE(DATE(ain.ts_document), ai.dt_emission_boleto) AS dt_emission_boleto,
      COALESCE(DATE(ain.ts_due), ai.dt_due_boleto) AS dt_due_boleto,
      COALESCE(DATE(ain.ts_processing), ai.dt_processing_boleto) AS dt_processing_boleto,
      ai.dt_cancelation
    FROM union_promisses_agreements_installments AS ai
    INNER JOIN datalake_cyber_clean.contracts AS c
      ON ai.id_contract = c.id_contract
    LEFT JOIN datalake_cyber_clean.payments AS p
      ON ai.id_agreement_installment = p.id_agreement_installment
    LEFT JOIN datalake_cyber_clean.agreement_invoices AS ain
      ON ai.id_agreement = ain.id_agreement
        AND ai.installment_number = ain.installment_number
    LEFT JOIN datalake_cyber_clean.agreement_type AS at
      ON ai.agreement_type = at.id_agreement_type
    LEFT JOIN split_fees_between_installments AS f
      ON ai.id_agreement = f.id_agreement
  )
  SELECT
    CAST(id_agreement_installment AS STRING) AS id_agreement_installment,
    CAST(id_negotiation AS STRING) AS id_negotiation,
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
    discount_amount,
    amount_to_pay,
    agreement_balance_amount,
    paid_amount,
    dt_creation,
    dt_due,
    dt_paid,
    dt_emission_boleto,
    dt_due_boleto,
    dt_processing_boleto,
    dt_cancelation,
    NOW() AS ts_load
  FROM calculate_fields
