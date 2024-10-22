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
        id AS id_installment_charge,
        GET_JSON_OBJECT(metadata, "$.our-number") AS our_number
    FROM datalake_trato_feito_clean.installment_charges
),
invoice_extra AS (
    SELECT
        ai.id_external AS id_invoice_extra,
        ai.id_installment
    FROM datalake_trato_feito_clean.accounting_installment AS ai
    LEFT JOIN datalake_trato_feito_clean.bill AS b
        ON ai.id_external = b.id_external
    WHERE b.external_status != 'canceled'
    QUALIFY ROW_NUMBER() OVER(PARTITION BY ai.id_installment ORDER BY IFNULL(b.dt_paid, DATE("2900-12-31"))) = 1
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
    COALESCE(external_index + 1, DENSE_RANK() OVER(PARTITION BY cp.id_negotiation ORDER BY cp.ts_created, cp.id_external)) AS installment_number,
    ie.id_invoice_extra,
    COALESCE(cc.our_number, cp.id_external) AS our_number,
    cp.status,
    cp.total_amount + cp.discount_amount - (cp.installment_interest + cp.installment_fee_amount + cp.installment_costs + cp.installment_lawyers_fee) AS original_debt_amount,
    cp.adm_fee_amount,
    cp.installment_fee_amount,
    cp.debts_fee_amount,
    cp.discount_amount,
    cp.total_amount,
    cp.installment_interest,
    cp.installment_costs,
    cp.installment_lawyers_fee,
    cp.credit_card_fee,
    cp.payment_type,
    cp.dt_due,
    cp.ts_paid_diff as ts_paid_difference,
    cp.ts_expired,
    cp.ts_created,
    cp.ts_updated,
    cp.ts_payment_updated AS ts_paid
FROM
    cte_pay AS cp
LEFT JOIN charges AS cc
    ON cp.id_installment_charge = cc.id_installment_charge
LEFT JOIN invoice_extra AS ie
    ON cp.id = ie.id_installment
