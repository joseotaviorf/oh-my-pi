WITH cash_flow_base AS
(
    SELECT
        s.id_external_offer AS sk_offer,
        DATE(st.ts_created) AS dt_created,
        COALESCE(SUM(ir.amount), 0) - COALESCE(SUM(otr.amount), 0) AS cash_flow_amount
    FROM
        datalake_monopoly_clean.sale AS s
    JOIN
        datalake_monopoly_clean.sale_transaction AS st
            ON s.id = st.id_sale
    LEFT JOIN
        datalake_monopoly_clean.income_reference AS ir
            ON st.id_income_reference = ir.id
    LEFT JOIN
        datalake_monopoly_clean.outcome_reference AS otr
            ON st.id_outcome_reference = otr.id
    GROUP BY 1, 2
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
        CAST((CAST(so.sale_price_agreed AS DECIMAL(10,2)) * CAST(so.brokerage_fee AS DECIMAL(5,4))) AS DECIMAL(10,2)) AS brokerage_amount,
        MIN(
            CASE
                WHEN CAST(cf.cash_flow_amount AS DECIMAL(10,2)) >= CAST((CAST(so.sale_price_agreed AS DECIMAL(10,2)) * CAST(so.brokerage_fee AS DECIMAL(5,4))) AS DECIMAL(10,2)) THEN dt_created
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
    CAST(so.sale_price_agreed AS DECIMAL(10,2)) AS sale_price_agreed,
    CAST(so.brokerage_fee AS DECIMAL(5,4)) AS brokerage_fee,
    ad.brokerage_amount,
    cf_total.cash_flow_amount AS total_cash_flow_amount,
    cf_total.cash_flow_amount - (ad.brokerage_amount) AS delta_total_cash_flow_to_broakerage_amount,
    cf.cash_flow_amount AS cash_flow_amount_when_payment_allowed,
    ad.dt_first_full_down_payment_event IS NOT NULL AS is_payment_allowed,
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
WHERE
    so.dt_sale_agreement_signed IS NOT NULL
