SELECT
    a.id_agreement AS id_negotiation,
    c.id_contract_external AS id_contract,
    c.id_client AS id_debtor,
    p.id_payment AS id_receipt,
    a.contract_group AS creditor,
    ai.status,
    CASE
        WHEN ai.status = 'Quebrado' THEN 'canceled'
        WHEN ai.status = 'Concluído' THEN 'paid'
        WHEN ai.status IN ('Pendente de Pagamento', 'Programado') THEN 'pending'
        ELSE ai.status
    END AS installment_status,
    p.payment_type,
    p.payment_method,
    ai.installment_number,
    ai.amount_to_pay,
    ai.interest_amount,
    ai.fees_amount,
    ai.tax_amount,
    ai.amortization_amount,
    ai.final_balance,
    p.payment_amount AS paid_amount,
    DATE(ai.ts_due_installment) AS dt_due,
    DATE(p.ts_payment) AS dt_paid
FROM datalake_cyber_clean.agreement_installments AS ai
INNER JOIN datalake_cyber_clean.agreements AS a
    ON a.id_agreement = ai.id_agreement
INNER JOIN datalake_cyber_clean.contracts AS c
  ON a.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.payments AS p
  ON a.id_agreement = p.id_agreement
LEFT JOIN datalake_cyber_clean.agreement_invoices AS ain
  ON ai.id_agreement = ain.id_agreement
    AND ai.installment_number = ain.installment_number
