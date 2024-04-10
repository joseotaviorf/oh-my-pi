WITH
deduplicate_payment AS (
    SELECT
        ts_updated,
        type,
        id_installment
    FROM datalake_trato_feito_clean.payment
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_created DESC) = 1
),
cte_pay AS (
    SELECT
        i.*,
        p.ts_updated AS ts_payment_updated,
        p.type AS payment_type,
        DATEDIFF(p.ts_updated, i.dt_due) AS ts_paid_diff
    FROM
        datalake_trato_feito_clean.installment AS i
    LEFT JOIN
        deduplicate_payment AS p
            ON p.id_installment = i.id
)
SELECT
    cp.id,
    cp.id_external,
    cp.id_negotiation,
    cp.status,
    cp.adm_fee_amount,
    cp.installment_fee_amount,
    cp.debts_fee_amount,
    cp.discount_amount,
    cp.total_amount,
    cp.payment_type,
    cp.dt_due,
    cp.ts_paid_diff as ts_paid_difference,
    cp.ts_expired,
    cp.ts_created,
    cp.ts_updated,
    cp.ts_payment_updated AS ts_paid
FROM
    cte_pay AS cp
