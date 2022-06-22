WITH cte_pay AS (
    SELECT
        i.*,
        p.ts_updated AS ts_payment_updated,
        p.type AS payment_type,
        DATEDIFF(p.ts_updated, i.dt_due) AS ts_paid_diff
    FROM
        datalake_trato_feito_clean.installment AS i
    LEFT JOIN
        datalake_trato_feito_clean.payment AS p
            ON p.id_installment = i.id
),
cte_purpose AS (
    SELECT
        i.`id`,
        inv.purpose AS purpose
    FROM
        datalake_trato_feito_clean.installment AS i
    LEFT JOIN
        datalake_trato_feito_clean.accounting_installment AS ai
            ON i.`id` = ai.id_installment
    LEFT JOIN
        datalake_retsuko_clean.invoice inv
            ON ai.id_external = inv.id_external
)

SELECT
    cp.id,
    cp.id_external,
    cp.id_negotiation,
    cp.id_bill,
    cp.status,
    cp.adm_fee_amount,
    cp.installment_fee_amount,
    cp.debts_fee_amount,
    cp.discount_amount,
    cp.total_amount,
    cp.payment_type,
    cpu.purpose,
    cp.dt_due,
    cp.ts_paid_diff as ts_paid_difference,
    cp.ts_created,
    cp.ts_updated,
    cp.ts_payment_updated AS ts_paid
FROM
    cte_pay AS cp
LEFT JOIN
    cte_purpose AS cpu
        ON cp.`id` = cpu.`id`
