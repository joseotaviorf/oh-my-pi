WITH
negotiation_status AS (
    SELECT
        i.id_customer,
        cp.installment_code AS id_negotiation,
        SUM(IF(LOWER(i.installment_situation) = "parcela paga", 1, 0)) AS paid,
        SUM(IF(LOWER(i.installment_situation) = "parcela em aberta", 1, 0)) AS open,
        SUM(IF(LOWER(i.installment_situation) = "acordo cancelado", 1, 0))   AS canceled
    FROM datalake_recupera_clean.creditor_pending AS cp
    INNER JOIN datalake_recupera_clean.installment AS i
        ON cp.installment_code = i.id_installment
    WHERE i.is_installment_active IS TRUE
    GROUP BY 1, 2
),
deduplicate_installment_detail AS (
    SELECT
        id_contract,
        id_creditor,
        id_customer,
        id_product,
        id_installment,
        dt_expiration_installment_agreement
    FROM datalake_recupera_clean.installment_detail
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, id_customer, id_contract, dt_expiration_installment_agreement ORDER BY MAKE_DATE(year,month,day) DESC) = 1
),
deduplicated_installment_canceled AS (
    SELECT
        id_installment,
        ts_canceled_installment
    FROM  datalake_recupera_clean.installment_canceled
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY MAKE_DATE(year,month,day) DESC) = 1
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
creditor_pending AS (
    SELECT
        installment_code AS id_installment,
        MIN(dt_installment_due_date) AS dt_due
    FROM datalake_recupera_clean.creditor_pending
    GROUP BY installment_code
)
SELECT
    STRING(i.id_installment) AS id_negotiation,
    isd.id_contract AS id_contract,
    i.id_operator,
    i.id_customer AS customer_document,
    CASE
        WHEN CAST(i.installment_number AS INT) = 0 AND LOWER(i.installment_situation) = "parcela paga" THEN CAST(i.id_installment AS INT)
        ELSE null
    END id_first_installment_paid,
    CASE
        WHEN LOWER(i.installment_situation) = "parcela paga" THEN i.id_customer
        ELSE NULL
    END AS id_paid_customer_document,
    i.receipt_code AS id_receipt,
    CASE
      WHEN i.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
      WHEN i.id_creditor IN (3,5) THEN "IQ QuintoCred"
      WHEN i.id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    i.is_special_installment,
    ci.indicator_content AS contract_status,
    CASE
        WHEN LOWER(i.installment_situation) = "parcela em aberta" THEN 'Em aberto'
        WHEN LOWER(i.installment_situation) = "parcela paga" THEN 'Pago'
        WHEN LOWER(i.installment_situation) = "acordo cancelado" AND dm.dt_paid IS NULL THEN 'Quebrado'
        WHEN LOWER(i.installment_situation) = "acordo cancelado" AND dm.dt_paid IS NOT NULL THEN 'Pago'
        ELSE NULL
    END AS installment_status,
    CASE
        WHEN ns.canceled > 0 THEN "QUEBRADO"
        WHEN ns.open > 0 THEN "ABERTO"
        WHEN ns.open = 0 AND ns.paid > 0 THEN "LIQUIDADO"
    END AS negotiation_status,
    CASE
      WHEN i.boleto_emission_indicator = "Parcelamento em boleto" THEN 'BOLETO'
      WHEN i.boleto_emission_indicator = "Pix" THEN 'PIX'
      WHEN i.boleto_emission_indicator = "Cartão de crédito" THEN 'CARTÃO'
    END AS payment_method,
    CAST(i.installments_amount AS INT) AS number_of_installments,
    (i.installments_amount+1) AS adjusted_number_of_installments,
    i.installment_number+1 AS installment_number,
    DATEDIFF(i.dt_installment, cp.dt_due) AS delay_days,
    i.main_amount,
    i.transfer_amount AS updated_balance,
    ROUND(dm.paid_amount,2) AS paid_amount,
    i.amount_to_pay,
    i.amount_fine,
    i.interest_fee_amount,
    i.default_interest_amount,
    i.adm_fee_amount,
    i.discount_amount,
    ROUND(i.transfer_amount - i.main_amount,2) AS charges,
    i.dt_installment AS dt_formalization,
    i.dt_due,
    dm.dt_paid,
    DATE(cd.ts_canceled_installment ) AS dt_canceled,
    CURRENT_DATE()-1 AS dt_base
FROM
    datalake_recupera_clean.installment AS i
LEFT JOIN
    deduplicate_installment_detail AS isd
        ON i.id_installment = isd.id_installment
        AND i.dt_due = isd.dt_expiration_installment_agreement
LEFT JOIN
    negotiation_status AS ns
        ON i.id_installment = ns.id_negotiation
LEFT JOIN
    detail_movement AS dm
        ON i.receipt_code = dm.receipt_code
        AND i.id_customer = dm.id_customer
LEFT JOIN
    deduplicated_installment_canceled AS cd
        ON cd.id_installment = i.id_installment
LEFT JOIN
    creditor_pending AS cp
        ON cp.id_installment = i.id_installment
LEFT JOIN
    datalake_recupera_clean.indicator_contracts ci
        ON ci.id_creditor = isd.id_creditor
            AND ci.id_product = isd.id_product
            AND ci.id_contract = isd.id_contract
            AND ci.id_customer = isd.id_customer
            AND LOWER(ci.id_indicator) = 'status'
WHERE
    i.dt_installment <= CURRENT_DATE() - 1
    AND i.is_installment_active IS TRUE
