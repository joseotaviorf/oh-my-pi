WITH
trato_feito_negotiation AS (
  SELECT
    id_negotiation_recupera,
    id_negotiation,
    is_contract_recurrent_debtor,
    has_renegotiated,
    status,
    qt_installments_paid,
    breached_installment,
    dt_expected_end,
    ts_paid_all
  FROM datalake_debt_recovery.negotiation
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_negotiation_recupera ORDER BY ts_created_at DESC) = 1 -- removes the exception in which 1 Trato-Feito negotiation ID has more than one Recupera negotiation ID. Ex: 97080

),
recupera_installment AS (
  SELECT DISTINCT
    id_installment AS id_negotiation,
    id_customer,
    advisory_code,
    agreement_type,
    expense_amount
  FROM datalake_recupera_clean.installment
  WHERE is_installment_active IS TRUE
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation, id_customer ORDER BY advisory_code DESC) = 1 -- The same negotiation may have different advisors
),
recupera_installment_detail AS (
  SELECT
    id_creditor,
    id_customer,
    id_installment AS id_negotiation,
    MAX(MAKE_DATE(year,month,day)) AS report_date,
    ROUND(SUM(discount_amount),2) AS discount_amount
  FROM datalake_recupera_clean.installment_detail
  GROUP BY 1,2,3
),
recupera_negotiation AS (
  SELECT
    id_creditor,
    id_negotiation,
    id_operator,
    customer_document,
    CASE
      WHEN negotiation_status = "ACORDO_LIQUIDADO" THEN "finished"
      WHEN negotiation_status = "ACORDO_CANCELADO"
        AND down_payment = "S" THEN "broken"
      WHEN negotiation_status = "ACORDO_CANCELADO"
        AND down_payment = "N" THEN "canceled"
      WHEN negotiation_status = "ACORDO_EM_ANDAMENTO"
        AND down_payment = "S" THEN "offset"
      WHEN negotiation_status = "ACORDO_EM_ANDAMENTO" THEN "started"
    END AS negotiation_status,
    origin_agreement,
    campaign_code,
    advisory,
    IF(agreement_in_delay = "S", TRUE, FALSE) AS agreement_in_delay,
    agreement_promise,
    promisse_payment_method,
    number_of_installments,
    IF(down_payment = "S", TRUE, FALSE) AS down_payment,
    total_negotiated_amount,
    agreement_discount_amount,
    down_payment_amount,
    due_amount,
    overdue_amount,
    total_amount_paid,
    total_next_due,
    dt_cancellation,
    dt_next_due,
    dt_promisse,
    dt_due_promisse
  FROM datalake_recupera.negotiation
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation ORDER BY MAKE_DATE(year,month,day) DESC) = 1
)
SELECT
    STRING(rn.id_negotiation) AS sk_negotiation,
    rn.customer_document AS sk_debtor,
    tfn.id_negotiation AS id_negotiation_trato_feito,
    rn.id_operator,
    CASE
      WHEN rn.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN rn.id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN rn.id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    ri.agreement_type,
    ri.advisory_code AS advisory,
    rn.origin_agreement,
    rn.campaign_code,
    tfn.is_contract_recurrent_debtor AS is_recurrent_debtor,
    COALESCE(tfn.status,rn.negotiation_status) AS negotiation_status,
    rn.agreement_promise,
    rn.promisse_payment_method,
    tfn.has_renegotiated,
    rn.agreement_in_delay,
    rn.down_payment AS is_down_payment_paid,
    rn.number_of_installments,
    INT(IFNULL(tfn.qt_installments_paid,0)) AS paid_installments,
    IFNULL(tfn.breached_installment,0) AS breached_installment,
    ri.expense_amount AS debt_amount,
    rn.total_negotiated_amount AS negotiated_amount,
    rid.discount_amount,
    rn.down_payment_amount,
    rn.due_amount,
    rn.overdue_amount,
    IFNULL(rn.total_amount_paid,0) AS paid_amount,
    rn.total_next_due,
    rn.dt_promisse,
    rn.dt_due_promisse,
    NULLIF(TRIM(rn.dt_cancellation),"") AS dt_cancellation,
    tfn.dt_expected_end,
    rn.dt_next_due,
    tfn.ts_paid_all,
    NOW() AS ts_load
FROM
  recupera_negotiation AS rn
INNER JOIN recupera_installment AS ri
  ON rn.id_negotiation = ri.id_negotiation
    AND rn.customer_document = ri.id_customer
LEFT JOIN trato_feito_negotiation AS tfn
  ON rn.id_negotiation = tfn.id_negotiation_recupera
LEFT JOIN recupera_installment_detail AS rid
  ON rn.id_negotiation = rid.id_negotiation
    AND rn.customer_document = rid.id_customer
    AND rn.id_creditor = rid.id_creditor
