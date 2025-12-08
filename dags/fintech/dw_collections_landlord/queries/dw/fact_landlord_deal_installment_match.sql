WITH deal_match_pp AS (
    SELECT
        m.id_invoice AS id_invoice_original,
        f.id_invoice AS id_invoice_deal,
        f.due_amount_adjustment AS due_amount_deal,
        f.status AS status_deal,
        f.payment_status AS payment_status_deal,
        f.purpose AS purpose_deal,
        f.dt_begin AS dt_begin_deal,
        f.dt_due AS dt_due_deal,
        f.dt_paid AS dt_paid_deal,
        f.dt_end AS dt_end_deal
    FROM
        dw_collections_landlord.fact_invoice_landlord_portfolio AS m
    LEFT JOIN
        dw_collections_landlord.fact_invoice_landlord_portfolio AS f
        ON f.tipo_fat <> "original_invoice"
        AND f.id_contract = m.id_contract
        AND f.due_amount_adjustment = m.due_amount
        AND f.id_account = m.id_account
    WHERE
        (m.tipo_fat = 'original_invoice' AND m.due_amount_adjustment <> 0)
        AND m.status = 'written-down'
        AND f.id_invoice IS NOT NULL
),
order_deal_match AS (
    SELECT
        id_invoice_original,
        id_invoice_deal,
        due_amount_deal,
        status_deal,
        payment_status_deal,
        purpose_deal,
        dt_begin_deal,
        dt_due_deal,
        dt_paid_deal,
        dt_end_deal,
        ROW_NUMBER() OVER(PARTITION BY id_invoice_original ORDER BY id_invoice_deal DESC) AS rn_deal_order
    FROM deal_match_pp
)
SELECT
    id_invoice_original,
    id_invoice_deal,
    status_deal,
    payment_status_deal,
    purpose_deal,
    due_amount_deal,
    rn_deal_order,
    dt_begin_deal,
    dt_due_deal,
    dt_paid_deal,
    dt_end_deal
FROM order_deal_match
