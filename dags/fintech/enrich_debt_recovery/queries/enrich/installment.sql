WITH
deduplicate_payment AS (
    SELECT
        ts_updated,
        type,
        id_installment
    FROM datalake_trato_feito_clean.payment
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_created DESC) = 1
),
charges AS (
    SELECT DISTINCT
        id_installment,
        GET_JSON_OBJECT(metadata, "$.our-number") AS our_number
    FROM datalake_trato_feito_clean.installment_charges
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
    COALESCE(external_index, DENSE_RANK() OVER(PARTITION BY cp.id_negotiation ORDER BY cp.ts_created, cp.id_external)) AS installment_number,
    c.our_number,
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
LEFT JOIN charges AS c
    ON c.id_installment = cp.id
