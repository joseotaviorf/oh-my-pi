WITH
extract_array_credit_card_fee AS (
  SELECT
    id,
    GET_JSON_OBJECT(payload, "$.debts[*].debts_fee_amount") AS debt_array_string
  FROM datalake_trato_feito_clean.negotiation
),
extract_total_credit_card_fee AS (
    SELECT
        id,
        ROUND(
            AGGREGATE(
                SPLIT(REGEXP_REPLACE(debt_array_string, r"\[|\]",""), ","),
                CAST(0 AS double),  -- Accumulator has to be of the same type as the input
                (value, acc) -> value + acc)
        ,2) credit_card_fee_amount
    FROM extract_array_credit_card_fee
),
paid_installments AS (
    SELECT
        n.`id` AS id_negotiation,
        FIRST_VALUE(i.total_amount) OVER(PARTITION BY n.`id` ORDER BY i.ts_updated) AS down_payment_amount,
        IF(i.status = 'paid', i.total_amount, 0) AS total_amount,
        IF(i.status = 'paid', i.ts_updated, NULL) AS ts_updated
    FROM
       datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN
        datalake_trato_feito_clean.installment AS i
            ON n.id = i.id_negotiation
),
cte_paid AS (
    SELECT
        id_negotiation,
        down_payment_amount,
        SUM(total_amount) AS paid_amount,
        COUNT(id_negotiation) AS qt_paid,
        MIN(ts_updated) AS ts_first_payment,
        MAX(ts_updated) AS ts_last_payment
    FROM paid_installments
    GROUP BY 1,2
),
cte_installments AS (
    SELECT
        n.`id` AS id_negotiation,
        COUNT(i.`id`) AS qt_installments,
        SUM(i.total_amount) AS total_expected_amount,
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
    -- If the invoice that exists in the debt table exists in the account_installment it means that it is the extra invoice created by another broken negotiation, i.e, the current negotiation is a renegotiation
    SELECT
        d.id_negotiation,
        BOOLEAN(SUM(IF(ac.id IS NOT NULL, 1, 0))) AS renegotiated
    FROM
        datalake_trato_feito_clean.debt AS d
    LEFT JOIN
        datalake_trato_feito_clean.accounting_installment AS ac
            ON ac.id_external = d.id_external
    GROUP BY 1
),
cte_ts_breach AS (
    SELECT
        n.`id` AS id_negotiation,
        MIN(i.ts_expired) AS ts_breach
    FROM
        datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN
        datalake_trato_feito_clean.installment AS i
            ON n.id = i.id_negotiation
    WHERE
        i.status <> 'paid'
    GROUP BY 1
),
cte_installment_order AS (
    SELECT
        i.id_negotiation,
        ROW_NUMBER() OVER(PARTITION BY i.id_negotiation ORDER BY i.dt_due ASC) AS installment_number,
        i.ts_expired
    FROM
        datalake_trato_feito_clean.installment AS i
),
cte_breach AS (
    SELECT
        cb.id_negotiation,
        cb.ts_breach,
        co.installment_number AS breached_installment
    FROM
        cte_ts_breach AS cb
    LEFT JOIN
        cte_installment_order AS co
            ON cb.id_negotiation = co.id_negotiation
            AND cb.ts_breach = co.ts_expired
),
cte_debts AS (
    SELECT
        id_negotiation,
        SUM(original_amount) AS negotiation_original_amount,
        SUM(discount_amount) AS negotiation_discount_amount,
        SUM(interest_fee_amount) AS interest_fee_amount,
        SUM(fine_fee_amount) AS fine_fee_amount,
        SUM(interest_fee_amount) + SUM(fine_fee_amount) AS negotiation_fees_amount
    FROM
        datalake_trato_feito_clean.debt AS d
    GROUP BY 1
)

SELECT
    n.`id` AS id_negotiation,
    n.id_collector_external AS id_negotiation_recupera,
    n.id_debtor_external AS id_contract,
    CONCAT(d.origin, "_", d.type) AS debtor,
    c.name AS collector,
    n.status,
    ci.qt_installments,
    cp.qt_paid AS qt_installments_paid,
    ci.total_expected_amount,
    IFNULL(cp.down_payment_amount, 0) AS down_payment_amount,
    cp.paid_amount,
    d.negotiation_original_amount,
    d.negotiation_discount_amount,
    d.interest_fee_amount,
    d.fine_fee_amount,
    d.negotiation_fees_amount,
    cc.credit_card_fee_amount,
    cb.breached_installment,
    cr.recurrent AS is_contract_recurrent_debtor,
    COALESCE(crn.renegotiated, False) AS has_renegotiated,
    ci.dt_expected_end,
    cp.ts_first_payment,
    CASE
        WHEN ci.qt_installments = cp.qt_paid THEN cp.ts_last_payment
        ELSE NULL
    END AS ts_paid_all,
    cb.ts_breach,
    n.ts_created AS ts_created_at
FROM
    datalake_trato_feito_clean.negotiation AS n
LEFT JOIN
    datalake_trato_feito_clean.debtor AS d
        ON n.id_debtor = d.id
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
LEFT JOIN extract_total_credit_card_fee AS cc
    ON cc.`id` = n.`id`
LEFT JOIN datalake_trato_feito_clean.collector AS c
    ON n.id_collector = c.id
