WITH
deduplicate_trato_feito_installment AS (
  SELECT
    id_contract,
    id_negotiation,
    id_negotiation_recupera
  FROM datalake_debt_recovery.negotiation
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_negotiation_recupera ORDER BY ts_created_at DESC) = 1
),
trato_feito_installment AS (
  SELECT
    n.id_contract,
    i.id_negotiation,
    n.id_negotiation_recupera,
    i.id AS id_installment,
    ai.id_external AS id_invoice_extra,
    DENSE_RANK() OVER(PARTITION BY n.id_contract, i.id_negotiation ORDER BY i.ts_created, i.id_external) AS installment_number,
    i.status AS installment_status,
    i.id_external AS id_receipt
  FROM
    datalake_debt_recovery.installment AS i
  INNER JOIN
    deduplicate_trato_feito_installment AS n
      ON i.id_negotiation = n.id_negotiation
  LEFT JOIN datalake_trato_feito_clean.accounting_installment AS ai
    ON ai.id_installment = i.id
),
recupera_installment AS (
  SELECT
    id_customer,
    id_creditor,
    id_installment AS id_negotiation,
    receipt_code AS id_receipt,
    is_special_installment,
    installment_number+1 AS installment_number,
    amount_to_pay,
    amount_fine,
    interest_fee_amount,
    default_interest_amount,
    adm_fee_amount
  FROM datalake_recupera_clean.installment
  WHERE is_installment_active IS TRUE
),
nexxera_confirmation AS (
  SELECT
      dt_due,
      dt_occurrence_code AS dt_paid,
      substr(our_number, 1,8) AS id_receipt,
      net_amount AS paid_amount,
      due_amount
  FROM
      datalake_nexxera.cnab_charges_recupera
  WHERE
      occurrence_code = '06'
  QUALIFY
      ROW_NUMBER() OVER(PARTITION BY our_number, occurrence_code ORDER BY dt_occurrence_code DESC) = 1
)
SELECT DISTINCT
    CONCAT(i.id_negotiation,"-",INT(i.installment_number)) AS sk_negotiation_installment,
    STRING(i.id_negotiation) AS sk_negotiation,
    i.customer_document AS sk_debtor,
    tfi.id_installment,
    tfi.id_invoice_extra,
    COALESCE(ri.id_receipt, tfi.id_receipt) AS id_receipt,
    i.installment_number,
    CASE
        WHEN ri.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
        WHEN ri.id_creditor IN (3,5) THEN "IQ QuintoCred"
        WHEN ri.id_creditor IN (2,6) THEN "PP QuintoAndar"
      END AS creditor,
    ri.is_special_installment,
    CASE
        WHEN tfi.installment_status = 'paid' OR i.installment_status = 'Pago' THEN 'paid'
        WHEN tfi.installment_status IS NULL AND i.installment_status = 'Quebrado' THEN 'canceled'
        WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN 'paid' -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
        WHEN tfi.installment_status IS NULL AND i.installment_status = 'Em aberto' THEN 'pending'
        ELSE tfi.installment_status
    END AS installment_status,
    i.delay_days,
    i.main_amount,
    ri.amount_to_pay,
    i.updated_balance,
    ri.amount_fine,
    ri.interest_fee_amount,
    ri.default_interest_amount,
    ri.adm_fee_amount,
    CASE
        WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN nx.paid_amount -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
        ELSE i.paid_amount
    END AS paid_amount,
    i.dt_formalization AS dt_creation,
    i.dt_due,
    CASE
        WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN nx.dt_paid -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
        ELSE i.dt_paid
    END AS dt_paid,
    i.dt_canceled,
    NOW() AS ts_load
FROM
    datalake_recupera.installment AS i
INNER JOIN
    recupera_installment AS ri
        ON ri.id_customer = i.customer_document
        AND ri.id_negotiation = i.id_negotiation
        AND ri.installment_number = i.installment_number
LEFT JOIN
    trato_feito_installment AS tfi
        ON tfi.id_contract = i.id_contract
        AND tfi.id_negotiation_recupera = i.id_negotiation
        AND tfi.installment_number = i.installment_number
LEFT JOIN
    nexxera_confirmation AS nx
        ON nx.id_receipt = COALESCE(ri.id_receipt, tfi.id_receipt)
        AND nx.dt_due = i.dt_due
