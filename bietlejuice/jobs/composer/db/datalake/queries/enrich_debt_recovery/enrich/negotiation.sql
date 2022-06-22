WITH cte_paid AS (
    SELECT
        n.`id` AS id_negotiation,
        SUM(i.total_amount) AS paid_amount,
        COUNT(i.`id`) AS qt_paid,
        MAX(i.ts_updated) AS ts_last_payment
    FROM
        datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN
        datalake_trato_feito_clean.installment AS i
            ON n.id = i.id_negotiation
    WHERE
        i.status = 'paid'
    GROUP BY 1
),
cte_installments AS (
    SELECT
        n.`id` AS id_negotiation,
        COUNT(i.`id`) AS qt_installments,
        SUM(i.total_amount) AS total_expected_amout,
        MAX(i.dt_due) AS dt_expected_end
    FROM
        datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN
        datalake_trato_feito_clean.installment AS i
            ON n.`id` = i.id_negotiation
    GROUP BY 1
),
cte_recurrent AS (
    SELECT
        `id` AS id_negotiation,
        BOOLEAN(CASE WHEN COUNT(id_debtor_external) > 1 THEN 1 ELSE 0 END) AS recurrent
    FROM datalake_trato_feito_clean.negotiation
    GROUP BY 1
),
cte_renegotiated AS (
    SELECT
        n.`id` as id_negotiation,
        BOOLEAN(SUM(CASE WHEN b.status = 'offset' THEN 1 ELSE 0 END)) AS renegotiated
    FROM
        datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN
        datalake_trato_feito_clean.installment AS i
            ON n.id = i.id_negotiation
    LEFT JOIN
        datalake_trato_feito_clean.bill AS b
            ON i.id_bill = b.id
    GROUP BY 1
),
cte_breach AS (
    WITH cte_ts_breach AS (
        SELECT
            n.`id` as id_negotiation,
            MIN(b.ts_created) AS ts_breach
        FROM
            datalake_trato_feito_clean.negotiation AS n
        LEFT JOIN
            datalake_trato_feito_clean.installment AS i
                ON n.id = i.id_negotiation
        RIGHT JOIN
            datalake_trato_feito_clean.bill AS b
                ON i.id_bill = b.id
        WHERE
            b.status <> 'paid'
        GROUP BY 1
    ),
    cte_installment_order AS (
        SELECT
            i.id_negotiation,
            i.id,
            i.dt_due,
            ROW_NUMBER() OVER(PARTITION BY i.id_negotiation ORDER BY i.dt_due ASC) AS installment_number,
            b.ts_created
        FROM
            datalake_trato_feito_clean.installment AS i
        LEFT JOIN
            datalake_trato_feito_clean.bill AS b
                ON i.id_bill = b.id
    )
    SELECT
        cb.id_negotiation,
        cb.ts_breach,
        co.installment_number AS breached_installment
    FROM
        cte_ts_breach AS cb
    LEFT JOIN
        cte_installment_order AS co
            ON cb.id_negotiation = co.id_negotiation
            AND cb.ts_breach = co.ts_created
),
cte_debts AS (
    SELECT
        id_negotiation,
        SUM(original_amount) AS negotiation_original_amount,
        SUM(discount_amount) AS negotiation_discount_amount,
        SUM(interest_fee_amount) + SUM(fine_fee_amount) AS negotiation_fees_amount
    FROM
        datalake_trato_feito_clean.debt AS d
    GROUP BY 1
)

SELECT
    n.`id` AS id_negotiation,
    n.id_debtor_external AS id_contract,
    n.status,
    ci.qt_installments,
    cp.qt_paid AS qt_installments_paid,
    ci.total_expected_amout,
    cp.paid_amount,
    d.negotiation_original_amount,
    d.negotiation_discount_amount,
    d.negotiation_fees_amount,
    cb.breached_installment,
    cr.recurrent AS is_contract_recurrent_debtor,
    COALESCE(crn.renegotiated, False) AS has_renegotiated,
    ci.dt_expected_end,
    CASE
        WHEN ci.qt_installments = cp.qt_paid THEN cp.ts_last_payment
        ELSE NULL
    END AS ts_paid_all,
    cb.ts_breach,
    n.ts_created AS ts_created_at
FROM
    datalake_trato_feito_clean.negotiation AS n
LEFT JOIN
    cte_installments AS ci
        ON n.`id` = ci.id_negotiation
LEFT JOIN
    cte_paid AS cp
        ON ci.id_negotiation = cp.id_negotiation
LEFT JOIN
    cte_debts AS d
        ON n.`id` = d.id_negotiation
LEFT JOIN
    cte_recurrent AS cr
        ON n.`id` = cr.id_negotiation
LEFT JOIN
    cte_renegotiated AS crn
        ON n.`id` = crn.id_negotiation
LEFT JOIN
    cte_breach AS cb
        ON n.`id` = cb.id_negotiation
