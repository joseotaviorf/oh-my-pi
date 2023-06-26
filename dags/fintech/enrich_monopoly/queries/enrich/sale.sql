WITH old_dt_occurence_rule AS(
    WITH last_sale_transaction AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id_sale ORDER BY ts_created DESC) AS rw_sale_transaction
        FROM
            datalake_monopoly_clean.sale_transaction AS st
        WHERE
            st.event = 'income-down-payment'
            AND st.status = 'created'
        )
        SELECT
            s.id AS id_sale,
            s.id_external_offer,
            st.id_income_reference,
            MAX(ir.dt_income) AS dt_occurence,
            s.ts_created
        FROM
            datalake_monopoly_clean.sale AS s
        LEFT JOIN
            last_sale_transaction AS st
                ON st.id_sale = s.id
                AND rw_sale_transaction = 1
        LEFT JOIN
            datalake_monopoly_clean.income_reference AS ir
                ON st.id_income_reference = ir.id
        GROUP BY 1, 2, 3, 5
),
cash_flow_base AS
(
    SELECT
        s.id_external_offer AS sk_offer,
        DATE(st.ts_created) AS dt_created,
        SUM(COALESCE(ae.debit,0) - COALESCE(ae.credit,0)) AS cash_flow_amount
    FROM
        datalake_monopoly_clean.accounting_entry AS ae
    --LEFT JOIN
    --    datalake_monopoly_clean.account AS a
    --        ON ae.id_account = a.id
    LEFT JOIN
        datalake_monopoly_clean.sale_transaction AS st
            ON ae.id_sale_transaction = st.id
    LEFT JOIN
        datalake_monopoly_clean.sale AS s
            ON st.id_sale = s.id
    --WHERE
    --    a.id IN (8, 23) -- 8 Itaú | 23 Stark Bank
    GROUP BY
        1, 2
),
cash_flow AS
(
    SELECT
        sk_offer,
        dt_created,
        SUM(cash_flow_amount) OVER (PARTITION BY sk_offer ORDER BY dt_created ASC) AS cash_flow_amount
    FROM
        cash_flow_base
),
allow_date AS
(
    SELECT
        so.id_offer,
        so.sale_price_agreed * so.brokerage_fee AS brokerage_amount,
        MIN(
            CASE
                WHEN cf.cash_flow_amount >= so.sale_price_agreed * so.brokerage_fee THEN dt_created
            ELSE NULL
            END
        ) AS dt_first_full_down_payment_event,
        MAX(dt_created) AS dt_paid_last_update
    FROM
        datalake_offer.sale_offer AS so
    LEFT JOIN
        cash_flow AS cf
            ON cf.sk_offer = so.id_offer
    GROUP BY 1, 2
)
SELECT
    so.id_offer,
    ROUND(so.sale_price_agreed, 2) AS sale_price_agreed,
    so.brokerage_fee,
    so.sale_price_agreed * so.brokerage_fee AS brokerage_amount,
    cf_total.cash_flow_amount AS total_cash_flow_amount,
    cf_total.cash_flow_amount - (so.sale_price_agreed * so.brokerage_fee) AS delta_total_cash_flow_to_broakerage_amount,
    cf.cash_flow_amount AS cash_flow_amount_when_payment_allowed,
    ad.dt_first_full_down_payment_event IS NOT NULL AS is_payment_allowed,
    old_rule.dt_occurence AS dt_occurence_old,
    DATE(so.dt_sale_agreement_signed) AS dt_sale_agreement_signed,
    ad.dt_paid_last_update AS dt_total_cash_flow_amount_last_updated,
    ad.dt_first_full_down_payment_event AS dt_occurence
FROM
    datalake_offer.sale_offer AS so
LEFT JOIN
    allow_date AS ad
        ON ad.id_offer = so.id_offer
LEFT JOIN
    cash_flow AS cf
        ON cf.sk_offer = ad.id_offer
        AND cf.dt_created = ad.dt_first_full_down_payment_event
LEFT JOIN
    cash_flow AS cf_total
        ON cf_total.sk_offer = ad.id_offer
        AND cf_total.dt_created = ad.dt_paid_last_update
LEFT JOIN
    old_dt_occurence_rule AS old_rule
        ON old_rule.id_external_offer = so.id_offer
WHERE
    so.dt_sale_agreement_signed IS NOT NULL
