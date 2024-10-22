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
installments AS (
    SELECT
        id_negotiation,
        MAX(IF(installment_number = 1, payment_type, NULL)) AS promisse_payment_method,
        SUM(IF(installment_number = 1, total_amount, 0)) AS down_payment_amount,
        SUM(IF(status = 'paid', total_amount, 0)) AS paid_amount,
        COUNT(DISTINCT IF(status = 'paid', id, NULL)) AS qt_installments_paid,
        MAX(installment_number) AS qt_installments,
        SUM(total_amount) AS total_expected_amount,
        SUM(COALESCE(credit_card_fee, adm_fee_amount)) AS credit_card_fee_amount,
        SUM(installment_fee_amount) AS installment_fee_amount,
        SUM(installment_interest) AS installment_interest,
        SUM(installment_fee_amount + installment_interest) AS negotiation_fees_amount,
        SUM(debts_fee_amount) AS debts_fee_amount,
        SUM(discount_amount) AS discount_amount,
        SUM(installment_costs) AS installment_costs,
        SUM(installment_lawyers_fee) AS installment_lawyers_fee,
        MIN(IF(ts_paid IS NULL AND status NOT IN ('paid', 'pending', 'registered'), installment_number, NULL)) AS breached_installment,
        COUNT(DISTINCT IF(ts_paid IS NULL AND status NOT IN ('paid', 'pending', 'registered'), id, NULL)) AS total_breached_installments,
        MIN(IF(status = 'paid', ts_paid, NULL)) AS ts_first_payment,
        MAX(IF(status = 'paid', ts_paid, NULL)) AS ts_last_payment,
        MAX(dt_due) AS dt_expected_end,
        MIN(ts_expired) AS ts_breach
    FROM datalake_debt_recovery.installment
    GROUP BY 1
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
    n.id_collector_external AS id_negotiation_external,
    n.id_debtor_external AS id_contract,
    CONCAT(d.origin, "_", d.type) AS debtor,
    c.name AS collector,
    n.consultancy,
    n.status,
    i.promisse_payment_method,
    i.qt_installments,
    i.qt_installments_paid,
    i.total_expected_amount,
    i.down_payment_amount,
    i.paid_amount,
    d.negotiation_original_amount,
    COALESCE(i.discount_amount, d.negotiation_discount_amount) AS negotiation_discount_amount,
    COALESCE(i.installment_interest, d.interest_fee_amount) AS interest_fee_amount,
    COALESCE(i.installment_fee_amount, d.fine_fee_amount) AS fine_fee_amount,
    COALESCE(i.negotiation_fees_amount, d.negotiation_fees_amount) AS negotiation_fees_amount,
    COALESCE(i.credit_card_fee_amount, cc.credit_card_fee_amount) AS credit_card_fee_amount,
    i.breached_installment,
    i.total_breached_installments,
    cr.recurrent AS is_contract_recurrent_debtor,
    COALESCE(crn.renegotiated, False) AS has_renegotiated,
    i.dt_expected_end,
    i.ts_first_payment,
    CASE
        WHEN i.qt_installments = i.qt_installments_paid THEN i.ts_last_payment
        ELSE NULL
    END AS ts_paid_all,
    i.ts_breach,
    n.ts_created AS ts_created_at
FROM
    datalake_trato_feito_clean.negotiation AS n
LEFT JOIN
    datalake_trato_feito_clean.debtor AS d
        ON n.id_debtor = d.id
LEFT JOIN
    cte_debts AS d
        ON n.`id` = d.id_negotiation
LEFT JOIN
    cte_recurrent AS cr
        ON n.`id` = cr.id_negotiation
LEFT JOIN
    cte_renegotiated AS crn
        ON n.`id` = crn.id_negotiation
LEFT JOIN installments AS i
    ON n.`id` = i.id_negotiation
LEFT JOIN extract_total_credit_card_fee AS cc
    ON cc.`id` = n.`id`
LEFT JOIN datalake_trato_feito_clean.collector AS c
    ON n.id_collector = c.id
