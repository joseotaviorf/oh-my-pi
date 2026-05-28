WITH
    sap AS (
    SELECT
    id_finance_entity AS id_fatura,
    id_finance_entity_entry AS id_contract,
    credit AS mensalidade_por_contrato
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        (
            account_number = '113009'
            OR account_name IN ('Duplicatas a Receber VELO')
        )
        AND debit = 0
),
cobranca_billing AS (
    SELECT  DISTINCT
        COALESCE( sap.id_contract, e.propose ) AS id_propose,
        i.id_bill AS id_boleto,
        COALESCE(sap.id_fatura,e.id_billing_report) AS id_fatura,
        add_months( DATE( concat( cast( i.accrual_year AS VARCHAR(10) ), '-', cast( i.accrual_month AS VARCHAR(10) ), '-', '01') ), 1) AS dt_ref_boleto,
        COALESCE( sap.mensalidade_por_contrato, e.amount ) AS mensalidade_por_contrato,
        i.total_amount,
        i.status AS status_invoice,
        b.status  AS status_boleto,
        DATE( b.ts_paid ) AS dt_paid,
        DATE( b.ts_created ) AS dt_boleto_created,
        DATE( b.dt_due ) AS dt_due
    FROM
        datalake_rental_guarantee_platform_clean.billing_report i
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.bill b
        ON b.id = i.id_bill
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.entry e
        ON e.id_billing_report = i.id
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.propose p
        ON p.id = e.propose
    LEFT JOIN sap
        ON sap.id_fatura = cast(i.id AS varchar(10))
        and sap.id_contract = cast(p.id AS varchar(10))
    WHERE
        CONCAT( b.status , i.status ) NOT IN ('WRITTEN_DOWNCANCELED')
    QUALIFY
        ROW_NUMBER() OVER(
            PARTITION BY COALESCE( sap.id_contract, e.propose ), dt_ref_boleto
            ORDER BY b.ts_paid DESC, b.ts_created DESC
        ) = 1
)
SELECT
    id_propose,
    CONCAT( id_boleto, CONCAT( id_propose, REPLACE( dt_ref_boleto, '-', '' ))) AS id,
    id_boleto AS id_bill,
    "a_billing" AS origin_table,
    mensalidade_por_contrato AS value,
    CASE
        WHEN status_boleto IN ('PAID_AFTER_DUE_DATE', 'PAID', 'CONFIRMED')
            THEN value
    END AS value_paid,
    status_boleto AS status,
    CASE
        WHEN status_boleto IN ('PAID_AFTER_DUE_DATE','PAID')
            THEN 1
        WHEN status_boleto IN ('PROCESSING')
            THEN 2
        WHEN status_boleto IN ('OPEN')
            THEN 3
        WHEN status_boleto IN ('OVERDUE')
            THEN 4
        WHEN status_boleto IN ('WRITTEN_DOWN')
            THEN 5
        ELSE 99
    END AS order_status,
    "BILLING DIRETO" AS gateway,
    "BOLETO" AS billing_type,
    CAST( NULL AS VARCHAR(20) ) AS category,
    DATE( dt_due ) < current_date() AS is_overdue,
    dt_paid,
    dt_boleto_created AS dt_created,
    dt_ref_boleto AS dt_due,
    NOW() AS ts_load
FROM
    cobranca_billing
WHERE
    id_propose IS NOT NULL
