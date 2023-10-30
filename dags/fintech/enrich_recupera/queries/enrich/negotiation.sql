WITH carta_campanha AS (
    SELECT DISTINCT
      id_creditor,
      id_customer,
      REGEXP_EXTRACT(LOWER(occurence_description), r"acordo:\s*(\d+)") id_installment,
      CAST(REGEXP_EXTRACT(LOWER(occurence_description), r"carta campanha:\s*(\d+)") AS INT) campaign_code
    FROM
      datalake_recupera_clean.historical_records
    WHERE
      historical_code = "ACORDO"
      AND regexp_like(LOWER(occurence_description), ".*carta campanha.*") IS TRUE
),
all_installment AS (
  SELECT
    id_customer,
    id_installment,
    id_creditor,
    id_operator,
    receipt_code,
    boleto_emission_indicator,
    installments_amount,
    amount_to_pay,
    discount_amount,
    installment_number,
    installment_situation,
    is_installment_active,
    FIRST_VALUE(installment_situation) OVER(PARTITION BY id_customer, id_installment ORDER BY installment_number DESC) AS most_recent_installment_status,
    IF(installment_situation = "Parcela em aberta" AND DATE(dt_due) < CURRENT_DATE , "S", "N") AS agreement_in_delay,
    dt_installment,
    dt_due
  FROM datalake_recupera_clean.installment
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
    IF(r.id_receipt IS NOT NULL, "S", "N") AS down_payment,
    i.amount_to_pay
  FROM all_installment AS i
  LEFT JOIN datalake_recupera_clean.receipt AS r
    ON r.id_receipt = i.receipt_code
    AND r.type_receipt IN ("Ficha de Compensação – Boleto confirmado (pago)", "Cartão credito (recebido)","Pix pago")

  QUALIFY ROW_NUMBER() OVER(PARTITION BY i.id_customer, i.id_installment ORDER BY i.installment_number) = 1 --  installment_number = "000"


),
agreements AS (
  SELECT
    f.id_customer,
    CAST(f.id_installment AS INT) AS id_negotiation,
    f.id_creditor,
    f.id_operator,
    f.dt_promisse,
    f.dt_due_promisse,
    f.promisse_payment_method,
    f.number_of_installments,
    f.down_payment,
    i.most_recent_installment_status,
    i.agreement_in_delay,
    IF(i.installment_number = "000" AND i.installment_situation = "Parcela em aberta", "PROMESSA", "ACORDO") AS agreement_promise,
    ROUND(SUM(i.amount_to_pay),2) AS total_negotiated_amount, --Valor_Total_Negociado
    ROUND(SUM(i.discount_amount),2) AS agreement_discount_amount, -- Valor_Desconto_Acordo
    ROUND(MIN(CASE WHEN i.installment_number = "000" THEN i.amount_to_pay END),2) AS down_payment_amount,
    ROUND(SUM(IF(i.installment_situation = "Parcela em aberta" AND DATE(i.dt_due) >= CURRENT_DATE , i.amount_to_pay, 0)),2) AS due_amount,-- VALOR_A_VENCER
    ROUND(SUM(IF(i.installment_situation = "Parcela em aberta" AND DATE(i.dt_due) < CURRENT_DATE , i.amount_to_pay, 0)),2) AS outstanding_amount,-- VALOR_EM_ATRASO
    -- IF(installment_situation = "Parcela em aberta", MIN(dt_due), NULL) AS dt_next_due, -- Proximo_vencimento
    MIN(CASE WHEN i.installment_situation = "Parcela em aberta" THEN i.dt_due END) AS dt_next_due, -- Proximo_vencimento
    ROUND(SUM(CASE WHEN i.installment_situation = "Parcela em aberta" THEN i.amount_to_pay END),2) AS total_next_due, -- Total_Proximo_vencimento
    ROUND(SUM(CASE WHEN r.id_receipt IS NOT NULL THEN i.amount_to_pay END), 2) AS total_amount_paid
  FROM first_installment AS f
  INNER JOIN all_installment AS i
     ON f.id_installment = i.id_installment
      AND f.id_customer = i.id_customer
  LEFT JOIN datalake_recupera_clean.receipt AS r
    ON r.id_receipt = i.receipt_code
    AND r.type_receipt IN ("Ficha de Compensação – Boleto confirmado (pago)", "Cartão credito (recebido)","Pix pago")
  WHERE is_installment_active IS TRUE
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
deduplicate_installment_detail AS (
  SELECT
      id_installment,
      id_contract,
      id_creditor,
      id_product,
      id_customer,
      main_amount
    FROM datalake_recupera_clean.installment_detail
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, id_customer, id_contract, dt_expiration_installment_agreement ORDER BY year DESC, month desc, day desc) = 1
),
installment_detail AS (
  SELECT
    id_installment,
    id_contract,
    id_creditor,
    id_product,
    id_customer,
    ROUND(SUM(main_amount),2) AS original_debit_amount
  FROM deduplicate_installment_detail
  GROUP BY 1,2,3,4,5
),
deduplicate_records AS (
    SELECT
      id_customer,
      customer_document,
      customer_name,
      id_creditor
    FROM datalake_recupera_clean.records
    QUALIFY ROW_NUMBER() OVER(PARTITION by id_customer, customer_name ORDER BY dt_customer_registration DESC) = 1
)
SELECT DISTINCT
  r.customer_document,
  a.id_creditor,
  pd.id_contract,
  a.id_negotiation,
  a.id_operator,
  r.customer_name,
  op.collesction_customer_situation AS status,
  st.status_description,
  CASE
    WHEN ic.id_installment IS NOT NULL THEN 'ACORDO_CANCELADO'
    WHEN a.most_recent_installment_status = "Parcela paga" THEN 'ACORDO_LIQUIDADO'
    WHEN a.most_recent_installment_status = "Parcela em aberta" THEN 'ACORDO_EM_ANDAMENTO'
  END AS negotiation_status,
  c.campaign_code,
  a.promisse_payment_method,
  a.number_of_installments,
  CASE
    WHEN LOWER(o.operator_type) = "webservice" THEN 'Assessoria'
    WHEN c.campaign_code IS NOT NULL THEN 'Carta_Campanha'
    WHEN a.id_operator in ('LOJISTA', 'PORTAL') THEN 'Portal_Autonegociação'
    ELSE 'Operador'
  END AS origin_agreement,
  op.advisory_code AS advisory,
  a.down_payment,
  pd.original_debit_amount,
  a.total_negotiated_amount,
  a.agreement_discount_amount,
  a.down_payment_amount,
  a.due_amount,
  a.outstanding_amount,
  a.total_amount_paid,
  a.total_next_due,
  a.agreement_in_delay,
  a.agreement_promise,
  REPLACE(
    IFNULL((IFNULL(CAST(ic.ts_canceled_installment AS DATE), ' ')),''),'1900-01-01',''
  ) AS dt_cancellation,
  a.dt_next_due,
  a.dt_promisse,
  a.dt_due_promisse,
  NOW() AS ts_snapshot,
  YEAR(NOW()) AS year,
  MONTH(NOW()) AS month,
  DAY(NOW()) AS day
FROM deduplicate_records AS r
INNER JOIN agreements AS a
  ON r.id_customer = a.id_customer
INNER JOIN installment_detail AS pd
    ON a.id_creditor = pd.id_creditor
      AND a.id_customer = pd.id_customer
      AND a.id_negotiation = pd.id_installment
INNER JOIN datalake_recupera_clean.creditor_pending AS cp
    ON cp.id_creditor = pd.id_creditor
      AND cp.id_customer = pd.id_customer
      AND cp.id_contract = pd.id_contract
      AND cp.id_product = pd.id_product
      AND cp.installment_code = pd.id_installment
LEFT JOIN datalake_recupera_clean.operational_records AS op
    ON a.id_creditor = op.id_creditor
      AND r.id_customer = op.id_customer
LEFT JOIN datalake_recupera_clean.status AS st
    ON op.collesction_customer_situation = st.id_status
LEFT JOIN carta_campanha AS c
    ON c.id_customer = op.id_customer
      AND c.id_installment = a.id_negotiation
LEFT JOIN datalake_recupera_clean.installment_canceled AS ic
  ON ic.id_installment = a.id_negotiation
LEFT JOIN datalake_recupera_clean.operators AS o
  ON o.id_operator = a.id_operator
