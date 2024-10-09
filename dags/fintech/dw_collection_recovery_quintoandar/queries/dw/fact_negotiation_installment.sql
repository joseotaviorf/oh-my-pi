WITH
deduplicate_trato_feito_negotiation AS (
  SELECT
    id_contract,
    id_negotiation,
    id_negotiation_external,
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
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_negotiation_external ORDER BY ts_created_at DESC) = 1

),
trato_feito_installment AS (
  SELECT
    CONCAT(n.id_negotiation_external,"-",INT(i.installment_number)) AS id_negotiation_installment,
    n.id_negotiation_external,
    i.id AS id_installment_trato_feito,
    i.id_invoice_extra,
    i.installment_number,
    i.our_number,
    n.creditor,
    i.status AS installment_status,
    i.payment_type AS payment_method,
    NULL AS delay_days,
    NULL AS main_amount,
    NULL AS updated_balance,
    NULL AS fine_amount,
    NULL AS interest_fee_amount,
    NULL AS default_interest_amount,
    i.adm_fee_amount AS credit_card_fee_amount,
    i.discount_amount,
    i.total_amount AS amount_to_pay,
    IF(i.ts_paid IS NOT NULL, i.total_amount, NULL) AS paid_amount,
    DATE(i.ts_created) AS dt_creation,
    i.dt_due,
    DATE(i.ts_paid) AS dt_paid,
    IF(i.status = "canceled", DATE(i.ts_updated), NULL) AS dt_canceled,
    n.source,
    3 AS priority
  FROM
      datalake_debt_recovery.installment AS i
  INNER JOIN
      deduplicate_trato_feito_negotiation AS n
          ON i.id_negotiation = n.id_negotiation
  LEFT JOIN datalake_trato_feito_clean.payment
),
union_external_sources AS (
  SELECT DISTINCT
    CONCAT(id_negotiation, "-" , installment_number) AS id_negotiation_installment,
    id_negotiation AS id_negotiation_external,
    installment_number,
    our_number,
    creditor,
    installment_status,
    payment_method,
    NULL delay_days,
    NULL AS main_amount,
    agreement_balance_amount AS updated_balance,
    fine_amount,
    total_interest_amount AS interest_fee_amount,
    NULL AS default_interest_amount,
    credit_card_fee_amount,
    discount_amount,
    amount_to_pay,
    paid_amount,
    dt_creation,
    dt_due,
    dt_paid,
    dt_cancelation AS dt_canceled,
    'Cyber' AS source,
    1 AS priority
  FROM
    datalake_cyber_homolog.installment AS i
  WHERE creditor = "QuintoAndar"

  UNION DISTINCT

  SELECT DISTINCT
    CONCAT(id_negotiation, "-", INT(installment_number)) AS id_negotiation_installment,
    id_negotiation AS id_negotiation_external,
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
    main_amount, -- renomear para debt amount?
    updated_balance, -- talvez seja o agreement_balance_amount
    amount_fine AS fine_amount,
    interest_fee_amount,
    default_interest_amount, -- Deletar?
    adm_fee_amount AS credit_card_fee_amount, -- Deletar?
    discount_amount,
    amount_to_pay,
    paid_amount,
    dt_formalization AS dt_creation,
    dt_due,
    dt_paid,
    dt_canceled,
    'Recupera' AS source,
    2 AS priority
  FROM
    datalake_recupera.installment AS i
  WHERE LOWER(creditor) NOT LIKE "%quintocred%"

),
all_installments AS (
  SELECT
    COALESCE(ext.id_negotiation_installment, tf.id_negotiation_installment) AS id_negotiation_installment,
    COALESCE(ext.id_negotiation_external, tf.id_negotiation_external) AS id_negotiation_external,
    tf.id_installment_trato_feito,
    COALESCE(ext.installment_number, tf.installment_number) AS installment_number,
    COALESCE(ext.our_number, tf.our_number) AS our_number,
    tf.id_invoice_extra,
    COALESCE(ext.creditor, tf.creditor) AS creditor,
    COALESCE(ext.installment_status, tf.installment_status) AS installment_status,
    COALESCE(ext.payment_method, tf.payment_method) AS payment_method,
    COALESCE(ext.delay_days, tf.delay_days) AS delay_days,
    COALESCE(ext.main_amount, tf.main_amount) AS main_amount,
    COALESCE(ext.updated_balance, tf.updated_balance) AS updated_balance,
    COALESCE(ext.fine_amount, tf.fine_amount) AS fine_amount,
    COALESCE(ext.interest_fee_amount, tf.interest_fee_amount) AS interest_fee_amount,
    COALESCE(ext.default_interest_amount, tf.default_interest_amount) AS default_interest_amount,
    COALESCE(ext.credit_card_fee_amount, tf.credit_card_fee_amount) AS credit_card_fee_amount,
    COALESCE(ext.discount_amount, tf.discount_amount) AS discount_amount,
    COALESCE(ext.amount_to_pay, tf.amount_to_pay) AS amount_to_pay,
    COALESCE(ext.paid_amount, tf.paid_amount) AS paid_amount,
    COALESCE(ext.dt_creation, tf.dt_creation) As dt_creation,
    COALESCE(ext.dt_due, tf.dt_due) AS dt_due,
    COALESCE(ext.dt_paid, tf.dt_paid) AS dt_paid,
    COALESCE(ext.dt_canceled, tf.dt_canceled) AS dt_canceled,
    COALESCE(ext.source, tf.source) AS source
  FROM union_external_sources AS ext
  FULL OUTER JOIN trato_feito_installment AS tf
    ON ext.id_negotiation_installment = tf.id_negotiation_installment
  QUALIFY ROW_NUMBER() OVER(PARTITION BY ext.id_negotiation_installment ORDER BY ext.priority) = 1

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
    i.id_negotiation_installment AS sk_negotiation_installment,
    i.id_negotiation_external AS sk_negotiation,
    id_installment_trato_feito,
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
    i.payment_method,
    i.delay_days,
    i.main_amount,
    i.updated_balance,
    i.fine_amount,
    i.interest_fee_amount,
    i.default_interest_amount,
    i.credit_card_fee_amount,
    i.discount_amount,
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
