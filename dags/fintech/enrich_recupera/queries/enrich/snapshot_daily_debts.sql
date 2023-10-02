
WITH collection_base AS (
    SELECT
        r.id_creditor,
        r.id_customer,
        r.customer_name,
        s.status_description,
        hr.historical_code,
        hr.occurence_description,
        hr.ts_occurrence,
        opr.id_operator,
        opr.advisory_code
    FROM
        datalake_recupera_clean.records AS r
    INNER JOIN
        datalake_recupera_clean.operational_records AS opr
        ON r.id_creditor = opr.id_creditor
        AND r.id_customer = opr.id_customer
    INNER JOIN datalake_recupera_clean.status AS s
        ON opr.collesction_customer_situation = s.id_status
    LEFT JOIN datalake_recupera_clean.historical_records hr
        ON r.id_creditor = hr.id_creditor
        AND r.id_customer = hr.id_customer
    QUALIFY ROW_NUMBER() OVER(PARTITION BY r.id_creditor, r.id_customer ORDER BY hr.ts_occurrence DESC) = 1
),
debts AS (
    SELECT DISTINCT
        cb.id_creditor,
        cb.id_customer,
        cb.customer_name,
        cr.id_contract,
        cr.id_installment AS id_invoice,
        cr.installment_code,
        cr.main_amount AS invoice_amount,
        cr.dt_debt_due AS dt_due_invoice,
        cb.status_description AS status,
        cb.id_operator AS operator,
        opr.distributor_code AS distributor,
        cb.historical_code AS occurrence,
        cb.ts_occurrence,
        REPLACE(REPLACE(REPLACE(cb.occurence_description, CHAR(124),' - '), CHAR(13),''), CHAR(10), '') AS observation,
        ii.indicator_content AS invoice_type,
        NULLIF(opr.advisory_code,'') AS advisory
    FROM
        collection_base AS cb
    INNER JOIN
        datalake_recupera_clean.complementary_records AS cr
            ON cb.id_creditor = cr.id_creditor
            AND cb.id_customer = cr.id_customer
    INNER JOIN
        datalake_recupera_clean.operational_records AS opr
            ON opr.id_creditor = cb.id_creditor
            AND opr.id_customer = cb.id_customer
    LEFT JOIN
        datalake_recupera_clean.installments_indicators AS ii
            ON cb.id_creditor = ii.id_creditor
            AND cb.id_customer = ii.id_customer
            AND cr.id_contract = ii.id_contract
            AND cr.id_installment = ii.id_installment
            AND ii.id_indicator = "TIPOFAT"
    WHERE
        cb.id_creditor IN ('1', '3', '5')
)
SELECT DISTINCT
    d.id_creditor,
    d.id_customer,
    d.id_contract,
    i.id_installment,
    NULL AS id_invoice,
    d.customer_name,
    d.status,
    d.operator,
    d.distributor,
    d.occurrence,
    d.observation,
    d.invoice_type,
    d.advisory,
    i.installment_number,
    NULL AS invoice_amount,
    IFNULL(i.amount_to_pay,0) AS deal_amount,
    i.dt_due AS dt_due_agreement,
    NULL AS dt_due_invoice,
    d.ts_occurrence,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
    debts AS d
INNER JOIN
    datalake_recupera_clean.installment AS i
        ON i.id_installment = d.installment_code
WHERE
    i.is_installment_active IS TRUE
    AND i.installment_situation = 'Parcela em aberta'

UNION

SELECT DISTINCT
    d.id_creditor,
    d.id_customer,
    d.id_contract,
    i.id_installment,
    d.id_invoice,
    d.customer_name,
    d.status,
    d.operator,
    d.distributor,
    d.occurrence,
    d.observation,
    d.invoice_type,
    d.advisory,
    i.installment_number,
    d.invoice_amount,
    IFNULL(i.amount_to_pay, 0) AS deal_amount,
    i.dt_due AS dt_due_agreement,
    d.dt_due_invoice,
    d.ts_occurrence,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
    debts AS d
LEFT JOIN
    datalake_recupera_clean.installment AS i
        ON i.id_installment = d.installment_code
WHERE
    d.installment_code IS NULL
