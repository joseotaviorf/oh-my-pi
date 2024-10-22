WITH
deduplicate_trato_feito_negotiation AS (
  SELECT DISTINCT
    id_contract,
    id_negotiation,
    IFNULL(CAST(id_negotiation_external AS BIGINT), id_negotiation_external) AS id_negotiation_external,
    CASE
      WHEN debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
     CASE
      WHEN LOWER(collector) LIKE '%cyber%' THEN "Trato Feito - Cyber"
      WHEN LOWER(collector) LIKE '%recupera%' THEN "Trato Feito - Recupera"
      WHEN UPPER(collector) LIKE '%5A%' THEN "Trato Feito - Self Service"
    END AS source
  FROM
      datalake_debt_recovery.negotiation
  WHERE
    debtor != "velo_delinquency_tenant"
),
trato_feito_installment AS (
  SELECT
    CONCAT(n.id_negotiation_external, LPAD(INT(i.installment_number), 3, '0')) AS id_negotiation_installment,
    n.id_contract,
    n.id_negotiation_external,
    i.id AS id_installment_trato_feito,
    i.id_invoice_extra,
    i.installment_number,
    i.our_number,
    n.creditor,
    i.status AS installment_status,
    i.payment_type AS payment_method,
    NULL AS delay_days,
    original_debt_amount AS main_amount,
    NULL AS updated_balance,
    installment_fee_amount AS fine_amount,
    installment_interest AS interest_fee_amount,
    i.adm_fee_amount AS credit_card_fee_amount,
    i.installment_costs,
    i.installment_lawyers_fee,
    i.discount_amount,
    i.total_amount AS amount_to_pay,
    IF(i.ts_paid IS NOT NULL, i.total_amount, NULL) AS paid_amount,
    DATE(i.ts_created) AS dt_creation,
    i.dt_due,
    DATE(i.ts_paid) AS dt_paid,
    IF(i.status = "canceled", DATE(i.ts_updated), NULL) AS dt_canceled,
    n.source
  FROM
      datalake_debt_recovery.installment AS i
  INNER JOIN
      deduplicate_trato_feito_negotiation AS n
          ON i.id_negotiation = n.id_negotiation
),
cyber_installments AS (
  SELECT DISTINCT
    CONCAT(CAST(id_negotiation AS BIGINT), LPAD(INT(installment_number), 3, '0')) AS id_negotiation_installment,
    id_contract_external AS id_contract,
    CAST(id_negotiation AS BIGINT) AS id_negotiation_external,
    installment_number,
    our_number,
    creditor,
    installment_status,
    payment_method,
    NULL delay_days,
    original_amount AS main_amount,
    agreement_balance_amount AS updated_balance,
    fine_amount,
    total_interest_amount AS interest_fee_amount,
    credit_card_fee_amount,
    eviction_costs_amount AS installment_costs,
    honorarium_amount AS installment_lawyers_fee,
    discount_amount,
    amount_to_pay,
    paid_amount,
    dt_creation,
    dt_due,
    dt_paid,
    dt_cancelation AS dt_canceled,
    'Cyber' AS source
  FROM
    datalake_cyber.installment AS i
  WHERE creditor = "QuintoAndar"
),
recupera_installments AS (
  SELECT DISTINCT
    CONCAT(CAST(id_negotiation AS BIGINT), LPAD(INT(installment_number), 3, '0')) AS id_negotiation_installment,
    id_contract,
    CAST(id_negotiation AS BIGINT) AS id_negotiation_external,
    installment_number,
    id_receipt AS our_number,
    creditor,
    CASE
      WHEN installment_status = 'Pago' THEN 'paid'
      WHEN installment_status = 'Quebrado' THEN 'canceled'
      WHEN installment_status = 'Em aberto' THEN 'pending'
      ELSE installment_status
    END AS installment_status,
    payment_method,
    delay_days,
    main_amount,
    updated_balance,
    amount_fine AS fine_amount,
    default_interest_amount + interest_fee_amount AS interest_fee_amount,
    adm_fee_amount AS credit_card_fee_amount,
    discount_amount,
    amount_to_pay,
    paid_amount,
    dt_formalization AS dt_creation,
    dt_due,
    dt_paid,
    dt_canceled,
    'Recupera' AS source
  FROM
    datalake_recupera.installment AS i
  WHERE LOWER(creditor) NOT LIKE "%quintocred%"
),
all_installments AS (
  SELECT
    COALESCE(tf.id_negotiation_installment, ci.id_negotiation_installment, ri.id_negotiation_installment) AS id_negotiation_installment,
    COALESCE(tf.id_negotiation_external, ci.id_negotiation_external, ri.id_negotiation_external) AS id_negotiation_external,
    COALESCE(tf.id_contract, ci.id_contract, ri.id_contract) AS id_contract,
    tf.id_installment_trato_feito,
    COALESCE(tf.installment_number, ci.installment_number, ri.installment_number) AS installment_number,
    COALESCE(tf.our_number, ci.our_number, ri.our_number) AS our_number,
    tf.id_invoice_extra,
    COALESCE(tf.creditor, ci.creditor, ri.creditor) AS creditor,
    COALESCE(tf.installment_status, ci.installment_status, ri.installment_status) AS installment_status,
    COALESCE(tf.payment_method, ci.payment_method, ri.payment_method) AS payment_method,
    COALESCE(tf.delay_days, ci.delay_days, ri.delay_days) AS delay_days,
    COALESCE(tf.main_amount, ci.main_amount, ri.main_amount) AS main_amount,
    COALESCE(tf.updated_balance, ci.updated_balance, ri.updated_balance) AS updated_balance,
    COALESCE(tf.fine_amount, ci.fine_amount, ri.fine_amount, 0) AS fine_amount,
    COALESCE(tf.interest_fee_amount, ci.interest_fee_amount, ri.interest_fee_amount, 0) AS interest_fee_amount,
    COALESCE(tf.credit_card_fee_amount, ci.credit_card_fee_amount, ri.credit_card_fee_amount, 0) AS credit_card_fee_amount,
    COALESCE(tf.discount_amount, ci.discount_amount, ri.discount_amount) AS discount_amount,
    COALESCE(tf.installment_costs, ci.installment_costs, 0) AS installment_costs,
    COALESCE(tf.installment_lawyers_fee, ci.installment_lawyers_fee, 0) AS installment_lawyers_fee,
    COALESCE(tf.amount_to_pay, ci.amount_to_pay, ri.amount_to_pay) AS amount_to_pay,
    COALESCE(tf.paid_amount, ci.paid_amount, ri.paid_amount) AS paid_amount,
    COALESCE(tf.dt_creation, ci.dt_creation, ri.dt_creation) As dt_creation,
    COALESCE(tf.dt_due, ci.dt_due, ri.dt_due) AS dt_due,
    COALESCE(tf.dt_paid, ci.dt_paid, ri.dt_paid) AS dt_paid,
    COALESCE(tf.dt_canceled, ci.dt_canceled, ri.dt_canceled) AS dt_canceled,
    COALESCE(tf.source, ci.source, ri.source) AS source
  FROM trato_feito_installment AS tf
  FULL OUTER JOIN cyber_installments AS ci
    ON tf.id_negotiation_installment = ci.id_negotiation_installment AND tf.source = "Trato Feito - Cyber"
  FULL OUTER JOIN recupera_installments AS ri
    ON tf.id_negotiation_installment = ri.id_negotiation_installment AND tf.source = "Trato Feito - Recupera"

),
nexxera_confirmation AS (
  SELECT
      dt_due,
      dt_occurrence_code AS dt_paid,
      substr(our_number, 1,8) AS our_number,
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
    CONCAT(i.id_contract, i.id_negotiation_installment) AS sk_negotiation_installment,
    CONCAT(i.id_contract, CAST(i.id_negotiation_external AS STRING)) AS sk_negotiation,
    i.id_contract AS sk_contract,
    CAST(i.id_negotiation_external AS STRING) AS id_negotiation,
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
    i.delay_days,
    i.main_amount,
    i.updated_balance,
    i.fine_amount,
    i.interest_fee_amount,
    i.credit_card_fee_amount,
    i.installment_costs,
    i.installment_lawyers_fee,
    i.discount_amount,
    i.main_amount -
      ROUND(CASE
        WHEN i.discount_amount >= (i.fine_amount + i.interest_fee_amount + i.installment_costs + i.installment_lawyers_fee)
          THEN i.discount_amount - (i.fine_amount + i.interest_fee_amount + i.installment_costs + i.installment_lawyers_fee)
        ELSE 0 END
      , 2) AS net_amount,
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
    i.dt_canceled,
    NOW() AS ts_load
FROM
    all_installments AS i
LEFT JOIN
    nexxera_confirmation AS nx
        ON nx.our_number = i.our_number
        AND nx.dt_due = i.dt_due
LEFT JOIN datalake_retsuko.invoice AS ri
  ON i.id_invoice_extra = ri.id_external
