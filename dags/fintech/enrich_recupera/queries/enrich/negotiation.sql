WITH carta_campanha AS (
  SELECT DISTINCT
    id_creditor,
    id_customer,
    REGEXP_EXTRACT(LOWER(occurence_description), r"acordo:\s*(\d+)") id_installment,
    REGEXP_EXTRACT(LOWER(occurence_description), r"carta campanha:\s*(\d+)") campaign_code
  FROM
    datalake_recupera_clean.historical_records
  WHERE
    historical_code = "ACORDO"
    AND regexp_like(LOWER(occurence_description), ".*carta campanha.*") IS TRUE
),
first_installment AS (
  SELECT
    i.id_customer,
    i.id_installment,
    i.id_creditor,
    i.id_operator,
    i.dt_installment AS dt_promisse,
    i.dt_due AS dt_due_promisse,
    i.installment_situation,
    CASE
      WHEN i.boleto_emission_indicator = "Parcelamento em boleto" THEN 'BOLETO'
      WHEN i.boleto_emission_indicator = "Pix" THEN 'PIX'
      WHEN i.boleto_emission_indicator = "Cartão de crédito" THEN 'CARTÃO'
    END AS promisse_payment_method,
    i.installments_amount + 1 AS number_of_installments,
    IF(r.id_receipt IS NOT NULL, True, False) AS down_payment,
    i.amount_to_pay,
    i.expense_amount
  FROM datalake_recupera_clean.installment AS i
  LEFT JOIN datalake_recupera_clean.receipt AS r
    ON r.id_receipt = i.receipt_code
    AND r.type_receipt IN ("Ficha de Compensação – Boleto confirmado (pago)", "Cartão credito (recebido)","Pix pago")
  WHERE is_installment_active IS TRUE
  QUALIFY ROW_NUMBER() OVER(PARTITION BY i.id_customer, i.id_installment ORDER BY i.installment_number) = 1 --  installment_number = "000"
),
open_installment AS (
  SELECT
    id_customer,
    id_installment,
    ROUND(SUM(IF(DATE(dt_due) >= CURRENT_DATE , amount_to_pay, 0)),2) AS total_negotiated_to_be_due_amount,
    ROUND(SUM(IF(DATE(dt_due) < CURRENT_DATE , amount_to_pay, 0)),2) AS total_negotiated_overdue_amount,
    MIN(dt_due) AS dt_next_due,
    MAX(IF(DATE(dt_due) < CURRENT_DATE , True, False)) AS agreement_in_delay
  FROM datalake_recupera_clean.installment
  WHERE installment_situation = "Parcela em aberta" AND is_installment_active IS TRUE
  GROUP BY 1,2
),
deduplicate_advisory AS (
  SELECT
    id_installment AS id_negotiation,
    id_customer,
    advisory_code AS advisory,
    agreement_type
  FROM datalake_recupera_clean.installment
  WHERE is_installment_active IS TRUE
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_negotiation, id_customer ORDER BY advisory_code DESC) = 1 -- The same negotiation may have different advisors
),
detail_movement AS (
    SELECT
        id_customer,
        receipt_code,
        dt_paid,
        SUM(amount_paid) AS paid_amount
    FROM datalake_recupera_clean.detail_movement
    GROUP BY 1, 2, 3
),
active_installments AS (
  SELECT
    id_installment,
    id_customer,
    receipt_code,
    installment_number,
    installment_situation,
    is_special_installment,
    FIRST_VALUE(installment_situation) OVER(PARTITION BY id_customer, id_installment ORDER BY installment_number DESC) AS most_recent_installment_status,
    main_amount,
    amount_fine,
    interest_fee_amount,
    adm_fee_amount,
    discount_amount,
    amount_to_pay,
    dt_due,
    dt_paid
  FROM datalake_recupera_clean.installment
  WHERE is_installment_active IS TRUE
),
agreements AS (
  SELECT
    f.id_customer,
    f.id_installment AS id_negotiation,
    f.id_creditor,
    f.id_operator,
    f.dt_promisse,
    f.dt_due_promisse,
    f.promisse_payment_method,
    INT(f.number_of_installments) AS number_of_installments,
    f.down_payment,
    ROUND(f.expense_amount, 2) AS expense_amount,
    i.most_recent_installment_status,
    i.is_special_installment,
    IFNULL(o.agreement_in_delay, FALSE) AS agreement_in_delay,
    da.advisory,
    da.agreement_type,
    o.dt_next_due,
    o.total_negotiated_to_be_due_amount,
    o.total_negotiated_overdue_amount,
    MAX(IF(i.installment_number = "000", dm.dt_paid, NULL)) AS dt_down_payment,
    MAX(i.dt_due) AS dt_negotiation_expected_end,
    MAX(IF(dm.dt_paid IS NOT NULL AND dm.dt_paid <= CURRENT_DATE, dm.dt_paid, NULL)) AS dt_last_payment,
    COUNT(IF(dm.dt_paid IS NOT NULL AND dm.dt_paid <= CURRENT_DATE, i.id_installment, NULL)) AS paid_installments,
    ROUND(SUM(IF(i.installment_situation = "Parcela em aberta" AND i.dt_due = o.dt_next_due, i.amount_to_pay, 0)),2) AS total_next_due,
    MAX(CASE
      WHEN i.installment_number = "000" AND i.installment_situation = "Parcela em aberta" THEN "PROMESSA"
      WHEN i.installment_number = "000" AND i.installment_situation != "Parcela em aberta" THEN "ACORDO"
    END) AS agreement_promise,
    MAX(r.customer_name) AS customer_name,
    ROUND(SUM(i.main_amount), 2) AS original_debt_amount,
    ROUND(SUM(i.amount_fine), 2) AS total_fine_fee_amount,
    ROUND(SUM(i.interest_fee_amount), 2) AS total_interest_fee_amount,
    ROUND(SUM(i.adm_fee_amount), 2) AS total_adm_fee_amount,
    ROUND(SUM(i.discount_amount),2) AS negotiation_discount_amount,
    ROUND(SUM(i.amount_to_pay),2) AS total_negotiated_amount,
    ROUND(MIN(CASE WHEN i.installment_number = "000" THEN i.amount_to_pay END),2) AS down_payment_amount,
    ROUND(MIN(CASE WHEN i.installment_number = "000" THEN i.main_amount END),2) AS down_payment_amount_without_fees,
    ROUND(SUM(CASE WHEN r.id_receipt IS NOT NULL THEN i.amount_to_pay END), 2) AS total_amount_paid
  FROM active_installments AS i
  INNER JOIN first_installment AS f
     ON f.id_installment = i.id_installment
      AND f.id_customer = i.id_customer
  LEFT JOIN open_installment AS o
    ON o.id_installment = i.id_installment
      AND o.id_customer = i.id_customer
  LEFT JOIN datalake_recupera_clean.receipt AS r
    ON r.id_receipt = i.receipt_code
    AND r.type_receipt IN ("Ficha de Compensação – Boleto confirmado (pago)", "Cartão credito (recebido)","Pix pago")
  LEFT JOIN deduplicate_advisory AS da
    ON i.id_installment = da.id_negotiation
    AND i.id_customer = da.id_customer
  LEFT JOIN
    detail_movement AS dm
        ON i.receipt_code = dm.receipt_code
        AND i.id_customer = dm.id_customer
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
),
deduplicated_installment_canceled AS (
  SELECT
    id_installment,
    DATE(ts_canceled_installment)
  FROM datalake_recupera_clean.installment_canceled
  QUALIFY ROW_NUMBER() OVER(PARTITION by id_installment ORDER BY ts_load DESC) = 1
),
installment_detail AS (
  SELECT
    id_installment,
    id_contract,
    id_creditor,
    id_customer
  FROM datalake_recupera_clean.installment_detail
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, id_customer, BIGINT(id_contract), id_product, dt_expiration_installment_agreement ORDER BY year DESC, month desc, day desc) = 1
),
contract_data AS (
  SELECT
    id_customer,
    id_contract,
    id_creditor
  FROM datalake_recupera_clean.contracts
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer, id_creditor ORDER BY dt_contract_start DESC) = 1
),
deduplicate_records AS (
  SELECT
    id_customer,
    customer_document,
    customer_name,
    id_creditor
  FROM datalake_recupera_clean.records
  QUALIFY ROW_NUMBER() OVER(PARTITION by id_customer ORDER BY dt_customer_registration DESC) = 1
),
operational_records AS (
  SELECT DISTINCT
    id_creditor,
    id_customer,
    collesction_customer_situation
  FROM datalake_recupera_clean.operational_records
  WHERE
    -- Filter the most recent records from operational_records since this table is a stack snapshot
    year = {year}
    AND month = {month}
    AND day = {day}
)
SELECT DISTINCT
  a.id_creditor,
  CAST(COALESCE(pd.id_contract, cd.id_contract) AS BIGINT) AS id_contract,
  a.id_negotiation,
  a.id_operator,
  CASE
    WHEN a.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
    WHEN a.id_creditor IN (3,5) THEN "IQ QuintoCred"
    WHEN a.id_creditor IN (2,6) THEN "PP QuintoAndar"
  END AS creditor,
  a.is_special_installment,
  COALESCE(r.customer_document, a.id_customer) AS customer_document,
  COALESCE(r.customer_name, a.customer_name) AS customer_name,
  op.collesction_customer_situation AS status,
  st.status_description,
  CASE
    WHEN ic.id_installment IS NOT NULL THEN 'ACORDO_CANCELADO'
    WHEN a.most_recent_installment_status = "Parcela paga" THEN 'ACORDO_LIQUIDADO'
    WHEN a.most_recent_installment_status = "Parcela em aberta" THEN 'ACORDO_EM_ANDAMENTO'
  END AS negotiation_status,
  c.campaign_code,
  a.promisse_payment_method,
  CASE
    WHEN LOWER(o.operator_type) = "webservice" THEN 'Assessoria'
    WHEN c.campaign_code IS NOT NULL THEN 'Carta_Campanha'
    WHEN a.id_operator in ('LOJISTA', 'PORTAL') THEN 'Portal_Autonegociação'
    ELSE 'Operador'
  END AS origin_agreement,
  a.advisory,
  a.agreement_type,
  a.down_payment,
  a.agreement_in_delay,
  a.agreement_promise,
  a.number_of_installments,
  a.paid_installments,
  IF(ic.id_installment IS NOT NULL, a.number_of_installments - a.paid_installments, 0) AS breached_installments,
  COALESCE(a.original_debt_amount, 0) AS original_debt_amount,
  COALESCE(a.total_interest_fee_amount, 0) AS interest_fee_amount,
  COALESCE(a.total_adm_fee_amount, 0) AS adm_fee_amount,
  COALESCE(a.total_fine_fee_amount, 0) AS fine_fee_amount,
  COALESCE(a.expense_amount, 0) AS expense_amount,
  COALESCE(a.negotiation_discount_amount, 0) AS negotiation_discount_amount,
  COALESCE(a.total_negotiated_amount, 0) AS negotiated_amount,
  COALESCE(a.total_negotiated_to_be_due_amount, 0) AS negotiated_to_be_due_amount,
  COALESCE(a.total_negotiated_overdue_amount, 0) AS negotiated_overdue_amount,
  COALESCE(a.down_payment_amount, 0) AS down_payment_amount,
  COALESCE(a.down_payment_amount_without_fees, 0) AS down_payment_amount_without_fees,
  COALESCE(a.total_amount_paid, 0) AS total_amount_paid,
  a.total_next_due,
  DATE(NULLIF(TRIM(ic.ts_canceled_installment),"")) AS dt_cancellation,
  a.dt_next_due,
  a.dt_promisse,
  a.dt_due_promisse,
  a.dt_negotiation_expected_end,
  a.dt_down_payment,
  IF(a.number_of_installments = a.paid_installments, a.dt_last_payment, NULL) AS dt_paid_all,
  NOW() AS ts_snapshot,
  YEAR(NOW()) AS year,
  MONTH(NOW()) AS month,
  DAY(NOW()) AS day
FROM agreements AS a
LEFT JOIN deduplicate_records AS r
  ON r.id_customer = a.id_customer
LEFT JOIN installment_detail AS pd
    ON a.id_creditor = pd.id_creditor
      AND a.id_customer = pd.id_customer
      AND a.id_negotiation = pd.id_installment
LEFT JOIN contract_data AS c
  ON a.id_creditor = cd.id_creditor
    AND a.id_customer = cd.id_customer
LEFT JOIN operational_records AS op
    ON a.id_creditor = op.id_creditor
      AND r.id_customer = op.id_customer
LEFT JOIN datalake_recupera_clean.status AS st
    ON op.collesction_customer_situation = st.id_status
LEFT JOIN carta_campanha AS c
    ON c.id_customer = op.id_customer
      AND c.id_installment = a.id_negotiation
LEFT JOIN deduplicated_installment_canceled AS ic
    ON ic.id_installment = a.id_negotiation
LEFT JOIN datalake_recupera_clean.operators AS o
  ON o.id_operator = a.id_operator
