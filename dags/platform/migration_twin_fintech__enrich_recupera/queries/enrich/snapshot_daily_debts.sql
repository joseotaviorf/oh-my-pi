WITH
records_distributed_channels AS (
    SELECT
        id_creditor,
        id_customer,
        id_digital_channel,
        COUNT(*) OVER (PARTITION BY id_creditor, id_customer) count_multiples_records
    FROM datalake_recupera_clean.records_distributed_channels
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_creditor, id_customer ORDER BY DATE(ts_current_registration) DESC) = 1
),
operational_records AS (
  SELECT
    id_creditor,
    id_customer,
    id_operator,
    advisory_code,
    distributor_code,
    collesction_customer_situation
  FROM datalake_recupera_clean.operational_records
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

),
collection_base AS (
    SELECT
        opr.id_creditor,
        opr.id_customer,
        opr.id_operator AS operator,
        NULLIF(opr.advisory_code,'') AS advisory,
        opr.distributor_code AS distributor,
        r.customer_name,
        cr.id_contract,
        cr.installment_code,
        cr.id_installment AS id_invoice,
        cr.main_amount AS invoice_amount,
        cr.dt_debt_due AS dt_due_invoice,
        s.status_description  AS status,
        hr.historical_code AS occurrence,
        REPLACE(REPLACE(REPLACE(hr.occurence_description, CHAR(124),' - '), CHAR(13),''), CHAR(10), '') AS observation,
        hr.ts_occurrence,
        ii.indicator_content AS invoice_type,
        CASE
            WHEN rdc.count_multiples_records > 1 THEN "AMBOS"
            ELSE rdc.id_digital_channel
        END AS digital_channel
    FROM
       operational_records AS opr
    INNER JOIN datalake_recupera_clean.complementary_records AS cr
        ON opr.id_creditor = cr.id_creditor
            AND opr.id_customer = cr.id_customer
    LEFT JOIN datalake_recupera_clean.records AS r
        ON r.id_customer = opr.id_customer
    LEFT JOIN datalake_recupera_clean.status AS s
        ON opr.collesction_customer_situation = s.id_status
    LEFT JOIN datalake_recupera_clean.historical_records hr
        ON opr.id_creditor = hr.id_creditor
        AND opr.id_customer = hr.id_customer
    LEFT JOIN
        datalake_recupera_clean.installments_indicators AS ii
            ON opr.id_creditor = ii.id_creditor
            AND opr.id_customer = ii.id_customer
            AND cr.id_contract = ii.id_contract
            AND cr.id_installment = ii.id_installment
            AND ii.id_indicator = "TIPOFAT"
    LEFT JOIN records_distributed_channels AS rdc
        ON rdc.id_creditor = cr.id_creditor AND rdc.id_customer = cr.id_customer
    QUALIFY ROW_NUMBER() OVER(PARTITION BY hr.id_creditor, hr.id_customer, cr.id_installment  ORDER BY hr.ts_occurrence DESC) = 1
)
SELECT DISTINCT
    cb.id_creditor,
    cb.id_customer,
    cb.id_contract,
    NULL AS id_invoice,
    i.id_installment,
    cb.customer_name,
    cb.status,
    cb.operator,
    cb.distributor,
    cb.advisory,
    cb.occurrence,
    cb.observation,
    cb.invoice_type,
    cb.digital_channel,
    i.installment_number,
    NULL AS invoice_amount,
    IFNULL(i.amount_to_pay,0) AS deal_amount,
    NULL AS dt_due_invoice,
    i.dt_due AS dt_due_agreement,
    cb.ts_occurrence,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
    collection_base AS cb
INNER JOIN
    datalake_recupera_clean.installment AS i
        ON i.id_installment = cb.installment_code
WHERE
    cb.id_creditor IN ('1', '3', '5')
    AND i.is_installment_active IS TRUE
    AND i.installment_situation = 'Parcela em aberta'

UNION ALL

SELECT DISTINCT
    cb.id_creditor,
    cb.id_customer,
    cb.id_contract,
    cb.id_invoice,
    i.id_installment,
    cb.customer_name,
    cb.status,
    cb.operator,
    cb.distributor,
    cb.advisory,
    cb.occurrence,
    cb.observation,
    cb.invoice_type,
    cb.digital_channel,
    i.installment_number,
    cb.invoice_amount,
    IFNULL(i.amount_to_pay,0) AS deal_amount,
    cb.dt_due_invoice,
    i.dt_due AS dt_due_agreement,
    cb.ts_occurrence,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
    collection_base AS cb
LEFT JOIN
    datalake_recupera_clean.installment AS i
        ON i.id_installment = cb.installment_code
WHERE
    cb.id_creditor IN ('1', '3', '5')
    AND cb.installment_code IS NULL
