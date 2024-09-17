SELECT
    ai.id_agreement_installment,
    a.id_agreement AS id_negotiation,
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
    ai.amortization_amount,
    ai.interest_amount,
    ai.installments_fees_amount,
    ai.credit_card_fee_amount,
    at.fine_rate,
    ai.amount_to_pay,
    ai.agreement_balance_amount,
    p.payment_amount AS paid_amount,
    DATE(a.ts_agreement_creation) AS dt_creation,
    DATE(ai.ts_due_installment) AS dt_due,
    DATE(p.ts_payment) AS dt_paid,
  NOW() AS ts_load
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
