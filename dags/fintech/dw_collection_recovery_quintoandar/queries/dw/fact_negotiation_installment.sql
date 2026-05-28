WITH
nexxera_confirmation AS (
    SELECT * EXCEPT (_rn)
    FROM (
  SELECT
      dt_due,
      dt_occurrence_code AS dt_paid,
      substr(our_number, 1,8) AS our_number,
      net_amount AS paid_amount,
      due_amount,
        ROW_NUMBER() OVER (PARTITION BY our_number, occurrence_code ORDER BY dt_occurrence_code DESC) AS _rn
  FROM
      datalake_nexxera.cnab_charges_recupera
  WHERE
      occurrence_code = '06'
    )
    WHERE _rn = 1
),
calculate_discounts AS (
SELECT DISTINCT
    CONCAT(i.id_contract, i.id_negotiation_installment) AS sk_negotiation_installment,
    CONCAT(COALESCE(i.id_contract, 0), CAST(i.id_negotiation AS STRING)) AS sk_negotiation,
    i.id_contract AS sk_contract,
    CAST(i.id_negotiation AS STRING) AS id_negotiation,
    i.id_negotiation_installment AS id_installment,
    i.id_installment_trato_feito,
    CAST(i.id_invoice_extra AS BIGINT) AS id_invoice_extra,
    i.installment_number,
    i.our_number,
    i.creditor,
    i.source,
    CASE
      WHEN i.installment_status IN ('pending', 'registered') AND nx.paid_amount IS NOT NULL THEN 'paid' -- Only use nexxera if others call it 'registered'
      WHEN ri.status = 'paid' THEN 'paid'
      ELSE i.installment_status
    END AS installment_status,
    CASE
      WHEN UPPER(i.payment_method) IN ("CREDIT-CARD", "CARTÃO", "CARTÃO DE CRÉDITO") THEN "CARTÃO DE CRÉDITO"
      ELSE UPPER(i.payment_method)
    END AS payment_method,
    i.main_amount,
    i.updated_balance,
    i.fine_amount,
    i.interest_fee_amount,
    i.debts_fee_amount,
    i.credit_card_fee_amount,
    i.installment_costs,
    i.installment_lawyers_fee,
    i.main_amount + i.debts_fee_amount AS debt_amount,
    CASE
        WHEN source LIKE "%Recupera%" OR source LIKE "%Migração%"
          THEN (i.main_amount + i.debts_fee_amount) - i.amount_to_pay
      ELSE i.discount_amount
    END AS discount_amount,
    i.discount_to_original_amount,
    i.amount_to_pay,
    CASE
      WHEN i.installment_status IN ('pending', 'registered') AND nx.paid_amount IS NOT NULL THEN nx.paid_amount -- Only use nexxera if others call it 'registered'
      ELSE i.paid_amount
    END AS paid_amount,
    i.dt_creation,
    i.dt_due,
    CASE
      WHEN i.installment_status IN ('pending', 'registered') AND nx.paid_amount IS NOT NULL THEN nx.dt_paid -- Only use nexxera if others call it 'registered'
      ELSE COALESCE(DATE(ri.ts_paid), i.dt_paid)
    END AS dt_paid,
    IF(i.installment_status IN ('canceled','expired'), i.dt_canceled, NULL) AS dt_canceled
FROM
    datalake_collections_quintoandar.installment AS i
LEFT JOIN
    nexxera_confirmation AS nx
        ON nx.our_number = i.our_number
        AND nx.dt_due = i.dt_due
LEFT JOIN datalake_retsuko.invoice AS ri
  ON i.id_invoice_extra = ri.id_external
)
SELECT DISTINCT
    sk_negotiation_installment,
    sk_negotiation,
    sk_contract,
    id_negotiation,
    id_installment,
    id_installment_trato_feito,
    id_invoice_extra,
    installment_number,
    our_number,
    creditor,
    source,
    installment_status,
    payment_method,
    CAST(main_amount AS DECIMAL(14,2)) AS main_amount,
    CAST(updated_balance AS DECIMAL(14,2)) AS updated_balance,
    fine_amount,
    interest_fee_amount,
    CAST(debts_fee_amount AS DECIMAL(14,2)) AS debts_fee_amount,
    CAST(credit_card_fee_amount AS DECIMAL(14,2)) AS credit_card_fee_amount,
    installment_costs,
    installment_lawyers_fee,
    CAST(debt_amount AS DECIMAL(14,2)) AS debt_amount,
    CAST(discount_amount AS DECIMAL(14,2)) AS discount_amount,
    CAST(COALESCE(discount_to_original_amount,
      CASE
        WHEN discount_amount >= (debts_fee_amount + credit_card_fee_amount)
          THEN discount_amount - (debts_fee_amount + credit_card_fee_amount)
        ELSE 0
    END) AS DECIMAL(14,2)) AS discount_to_original,
    CAST(main_amount - COALESCE(discount_to_original_amount,
      CASE
        WHEN discount_amount >= (debts_fee_amount + credit_card_fee_amount)
          THEN discount_amount - (debts_fee_amount + credit_card_fee_amount)
        ELSE 0
    END) AS DECIMAL(14,2)) AS net_amount,
    amount_to_pay,
    paid_amount,
    dt_creation,
    dt_due,
    dt_paid,
    dt_canceled,
    NOW() AS ts_load
FROM calculate_discounts
