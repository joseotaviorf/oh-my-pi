WITH
deduplicate_trato_feito_negotiation AS (
  SELECT
    id_contract,
    id_negotiation,
    id_negotiation_recupera,
    CASE
      WHEN debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor
  FROM
      datalake_debt_recovery.negotiation
  WHERE
    debtor != "velo_delinquency_tenant"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_negotiation_recupera ORDER BY ts_created_at DESC) = 1
),
deduplicate_invoice_extra AS (
  SELECT
    a.id_external AS id_invoice,
    a.id_installment
  FROM
      datalake_trato_feito_clean.accounting_installment AS a
  LEFT JOIN datalake_retsuko.invoice AS i
    ON i.id_external = a.id_external
  WHERE i.status != "canceled"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY a.id_installment ORDER BY COALESCE(i.ts_payment_confirmation, i.ts_paid) DESC, i.ts_created ASC) = 1
),
trato_feito_installment AS (
  SELECT
    n.id_contract,
    i.id_negotiation,
    n.id_negotiation_recupera,
    n.creditor,
    i.id AS id_installment,
    i.id_invoice_extra,
    i.installment_number,
    i.status AS installment_status,
    i.id_external AS id_receipt,
    i.adm_fee_amount,
    i.discount_amount,
    i.total_amount,
    IF(i.ts_paid IS NOT NULL, i.total_amount, NULL) AS paid_amount,
    DATE(i.ts_created) AS dt_created,
    i.dt_due,
    DATE(i.ts_paid) AS dt_paid,
    IF(i.status = "canceled", DATE(i.ts_updated), NULL) AS dt_canceled
  FROM
      datalake_debt_recovery.installment AS i
  INNER JOIN
      deduplicate_trato_feito_negotiation AS n
          ON i.id_negotiation = n.id_negotiation
  LEFT JOIN
      deduplicate_invoice_extra AS ai
        ON ai.id_installment = i.id
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
    CONCAT(COALESCE(i.id_negotiation, tfi.id_negotiation_recupera),"-",INT(COALESCE(i.installment_number, tfi.installment_number))) AS sk_negotiation_installment,
    STRING(COALESCE(i.id_negotiation, tfi.id_negotiation_recupera)) AS sk_negotiation,
    i.customer_document AS sk_debtor,
    tfi.id_installment,
    CAST(tfi.id_invoice_extra AS BIGINT) AS id_invoice_extra,
    COALESCE(i.id_receipt, tfi.id_receipt) AS id_receipt,
    CAST(COALESCE(i.installment_number, tfi.installment_number) AS INT) AS installment_number,
    COALESCE(tfi.creditor, i.creditor) AS creditor,
    i.is_special_installment,
    CASE
      WHEN tfi.installment_status = 'paid' OR i.installment_status = 'Pago' THEN 'paid'
      WHEN tfi.installment_status IS NULL AND i.installment_status = 'Quebrado' THEN 'canceled'
      WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN 'paid' -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
      WHEN tfi.installment_status IS NULL AND i.installment_status = 'Em aberto' THEN 'pending'
      ELSE tfi.installment_status
    END AS installment_status,
    i.delay_days,
    i.main_amount,
    i.updated_balance,
    i.amount_fine,
    i.interest_fee_amount,
    i.default_interest_amount,
    COALESCE(i.adm_fee_amount, tfi.adm_fee_amount) AS adm_fee_amount,
    COALESCE(i.discount_amount, tfi.discount_amount) AS discount_amount,
    COALESCE(i.amount_to_pay, tfi.total_amount) AS amount_to_pay,
    CASE
      WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN nx.paid_amount -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
      ELSE COALESCE(i.paid_amount, tfi.paid_amount)
    END AS paid_amount,
    COALESCE(i.dt_formalization, tfi.dt_created) AS dt_creation,
    COALESCE(i.dt_due, tfi.dt_due) AS dt_due,
    CASE
          WHEN (tfi.installment_status IN ('pending', 'registered') OR i.installment_status = 'Em aberto') AND nx.paid_amount IS NOT NULL THEN nx.dt_paid -- Order of checks here matters!!!! Only use nexxera if others call it 'registered'
          ELSE COALESCE(i.dt_paid, tfi.dt_paid)
      END AS dt_paid,
    COALESCE(i.dt_canceled, tfi.dt_canceled) AS dt_canceled,
    NOW() AS ts_load
FROM
    datalake_recupera.installment AS i
FULL OUTER JOIN
    trato_feito_installment AS tfi
        ON tfi.id_negotiation_recupera = i.id_negotiation
        AND tfi.installment_number = i.installment_number
LEFT JOIN
    nexxera_confirmation AS nx
        ON nx.id_receipt = COALESCE(i.id_receipt, tfi.id_receipt)
        AND nx.dt_due = i.dt_due
WHERE i.creditor != "IQ QuintoCred"
