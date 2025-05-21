WITH
deduplicate_trato_feito_negotiation AS (
  SELECT DISTINCT
    id_contract,
    id_negotiation,
    qt_installments AS number_of_installments,
    IFNULL(CAST(id_negotiation_external AS BIGINT), id_negotiation_external) AS id_negotiation_external,
    CASE
      WHEN debtor = "rental_contract_landlord" THEN "PP QuintoAndar"
      WHEN debtor = "rental_contract_tenant" THEN "IQ QuintoAndar"
    END AS creditor,
    CASE
      WHEN LOWER(collector) LIKE '%cyber%' AND BIGINT(id_negotiation_external) < 10000000 THEN "Trato Feito - Cyber (Migração)"
      WHEN LOWER(collector) LIKE '%cyber%' AND BIGINT(id_negotiation_external) >= 10000000 THEN "Trato Feito - Cyber"
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
    n.number_of_installments,
    i.installment_number,
    i.our_number,
    n.creditor,
    i.status AS installment_status,
    i.payment_type AS payment_method,
    installment_fee_amount AS fine_amount,
    installment_interest AS interest_fee_amount,
    i.debts_fee_amount,
    IFNULL(i.adm_fee_amount, 0) AS credit_card_fee_amount,
    i.installment_costs,
    i.installment_lawyers_fee,
    i.discount_amount,
    i.total_amount AS amount_to_pay,
    IF(i.ts_paid IS NOT NULL, i.total_amount, NULL) AS paid_amount,
    DATE(i.ts_created) AS dt_creation,
    i.dt_due,
    DATE(i.ts_paid) AS dt_paid,
    i.dt_canceled,
    n.source
  FROM
      datalake_debt_recovery.installment AS i
  INNER JOIN
      deduplicate_trato_feito_negotiation AS n
          ON i.id_negotiation = n.id_negotiation
),
tf_negotiation_with_all_amounts_in_first_installment AS (
  SELECT
    id_negotiation_external,
    number_of_installments,
    SUM(debts_fee_amount) FILTER (WHERE installment_number = 1) AS debts_fee_amount_first_installment,
    SUM(debts_fee_amount) FILTER (WHERE installment_number > 1) AS debts_fee_amount_other_installments,
    SUM(discount_amount) FILTER (WHERE installment_number = 1) AS discount_amount_first_installment,
    SUM(discount_amount) FILTER (WHERE installment_number > 1) AS discount_amount_other_installments
  FROM
    trato_feito_installment
  WHERE
    number_of_installments > 1
    AND source IN ("Trato Feito - Recupera", "Trato Feito - Cyber (Migração)")
  GROUP BY 1,2
  HAVING (debts_fee_amount_first_installment > 0 AND debts_fee_amount_other_installments = 0)
    OR (discount_amount_first_installment > 0 AND discount_amount_other_installments = 0)
),
tf_divide_amount_by_installments AS (
  SELECT
    id_negotiation_external,
    FLOOR(debts_fee_amount_first_installment/number_of_installments,2) AS debt_fees,
    debts_fee_amount_first_installment - FLOOR(debts_fee_amount_first_installment/number_of_installments,2) * (number_of_installments - 1) AS last_debt_fees,
    FLOOR(discount_amount_first_installment/number_of_installments,2) AS discount,
    discount_amount_first_installment - FLOOR(discount_amount_first_installment/number_of_installments,2) * (number_of_installments - 1) AS last_discount
  FROM
    tf_negotiation_with_all_amounts_in_first_installment
),
tf_fix_debt_and_discount AS (
  SELECT
    i.* EXCEPT (i.debts_fee_amount, i.discount_amount),
    i.debts_fee_amount AS debts_fee_amount_original,
    CASE
      WHEN f.id_negotiation_external IS NOT NULL AND i.installment_number = i.number_of_installments THEN f.last_debt_fees
      WHEN f.id_negotiation_external IS NOT NULL AND i.installment_number != i.number_of_installments THEN f.debt_fees
      ELSE i.debts_fee_amount
    END AS debts_fee_amount,
    CASE
      WHEN f.id_negotiation_external IS NOT NULL AND i.installment_number = i.number_of_installments THEN f.last_discount
      WHEN f.id_negotiation_external IS NOT NULL AND i.installment_number != i.number_of_installments THEN f.discount
      ELSE i.discount_amount
    END AS discount_amount
  FROM
    trato_feito_installment AS i
  LEFT JOIN
    tf_divide_amount_by_installments AS f
      ON i.id_negotiation_external = f.id_negotiation_external
),
tf_all_fields_fix AS (
  SELECT
    *,
    amount_to_pay + discount_amount - debts_fee_amount AS main_amount
  FROM
    tf_fix_debt_and_discount
),
cyber_installments AS (
  SELECT DISTINCT
    id_agreement_installment AS id_negotiation_installment,
    id_contract_external AS id_contract,
    CAST(id_negotiation AS BIGINT) AS id_negotiation_external,
    installment_number,
    our_number,
    creditor,
    installment_status,
    payment_method,
    original_amount AS main_amount,
    agreement_balance_amount AS updated_balance,
    fine_amount,
    total_interest_amount AS interest_fee_amount,
    credit_card_fee_amount,
    eviction_costs_amount AS installment_costs,
    honorarium_amount AS installment_lawyers_fee,
    fine_amount + total_interest_amount + eviction_costs_amount + honorarium_amount  AS debts_fee_amount,
    discount_to_original_amount,
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
    CONCAT(CAST(ri.id_negotiation AS BIGINT), LPAD(INT(ri.installment_number), 3, '0')) AS id_negotiation_installment,
    COALESCE(tf.id_contract, ri.id_contract) AS id_contract,
    CAST(ri.id_negotiation AS BIGINT) AS id_negotiation_external,
    ri.installment_number,
    ri.id_receipt AS our_number,
    ri.creditor,
    CASE
      WHEN ri.installment_status = 'Pago' THEN 'paid'
      WHEN ri.installment_status = 'Quebrado' THEN 'canceled'
      WHEN ri.installment_status = 'Em aberto' THEN 'pending'
      ELSE ri.installment_status
    END AS installment_status,
    ri.payment_method,
    ri.main_amount,
    ri.updated_balance,
    ri.amount_fine AS fine_amount,
    ri.default_interest_amount + ri.interest_fee_amount AS interest_fee_amount,
    ri.amount_fine + ri.default_interest_amount + ri.interest_fee_amount AS debts_fee_amount,
    ri.adm_fee_amount AS credit_card_fee_amount,
    ri.discount_amount,
    ri.amount_to_pay,
    ri.paid_amount,
    ri.dt_formalization AS dt_creation,
    ri.dt_due,
    ri.dt_paid,
    ri.dt_canceled,
    'Recupera' AS source
  FROM
    datalake_recupera.installment AS ri
  LEFT JOIN tf_all_fields_fix AS tf
    ON
      tf.id_negotiation_installment =  CONCAT(CAST(ri.id_negotiation AS BIGINT), LPAD(INT(ri.installment_number), 3, '0'))
      AND tf.source = "Trato Feito - Recupera"
  WHERE LOWER(ri.creditor) NOT LIKE "%quintocred%"
)
  SELECT
    COALESCE(tf.id_negotiation_installment, ci.id_negotiation_installment, ri.id_negotiation_installment) AS id_negotiation_installment,
    CAST(COALESCE(tf.id_negotiation_external, ci.id_negotiation_external, ri.id_negotiation_external) AS STRING) AS id_negotiation, -- id_negotiation_external
    COALESCE(tf.id_contract, ci.id_contract, ri.id_contract) AS id_contract,
    tf.id_installment_trato_feito,
    CAST(tf.id_invoice_extra AS BIGINT) AS id_invoice_extra,
    COALESCE(tf.our_number, ci.our_number, ri.our_number) AS our_number,
    COALESCE(tf.installment_number, ci.installment_number, ri.installment_number) AS installment_number,
    COALESCE(tf.creditor, ci.creditor, ri.creditor) AS creditor,
    CONCAT_WS(" | ", tf.source, ci.source, ri.source) AS source,
    COALESCE(tf.installment_status, ci.installment_status, ri.installment_status) AS installment_status,
    COALESCE(tf.payment_method, ci.payment_method, ri.payment_method) AS payment_method,
    COALESCE(ci.main_amount, tf.main_amount, ri.main_amount) AS main_amount,
    COALESCE(ci.updated_balance, ri.updated_balance) AS updated_balance,
    COALESCE(ci.fine_amount, ri.fine_amount, tf.fine_amount, 0) AS fine_amount,
    COALESCE(ci.interest_fee_amount, ri.interest_fee_amount, tf.interest_fee_amount, 0) AS interest_fee_amount,
    COALESCE(ci.debts_fee_amount, tf.debts_fee_amount, ri.debts_fee_amount)AS debts_fee_amount,
    COALESCE(ci.credit_card_fee_amount, ri.credit_card_fee_amount, tf.credit_card_fee_amount, 0) AS credit_card_fee_amount,
    COALESCE(ci.discount_amount, tf.discount_amount, ri.discount_amount) AS discount_amount,
    ci.discount_to_original_amount,
    COALESCE(tf.installment_costs, ci.installment_costs, 0) AS installment_costs,
    COALESCE(tf.installment_lawyers_fee, ci.installment_lawyers_fee, 0) AS installment_lawyers_fee,
    COALESCE(tf.amount_to_pay, ci.amount_to_pay, ri.amount_to_pay) AS amount_to_pay,
    COALESCE(tf.paid_amount, ci.paid_amount, ri.paid_amount) AS paid_amount,
    COALESCE(tf.dt_creation, ci.dt_creation, ri.dt_creation) As dt_creation,
    COALESCE(tf.dt_due, ci.dt_due, ri.dt_due) AS dt_due,
    COALESCE(tf.dt_paid, ci.dt_paid, ri.dt_paid) AS dt_paid,
    COALESCE(tf.dt_canceled, ci.dt_canceled, ri.dt_canceled) AS dt_canceled,
    NOW() AS ts_load
  FROM tf_all_fields_fix AS tf
  FULL OUTER JOIN cyber_installments AS ci
    ON tf.id_negotiation_installment = ci.id_negotiation_installment
      AND tf.id_contract = ci.id_contract
  FULL OUTER JOIN recupera_installments AS ri
    ON tf.id_negotiation_installment = ri.id_negotiation_installment
      AND tf.id_contract = ri.id_contract
