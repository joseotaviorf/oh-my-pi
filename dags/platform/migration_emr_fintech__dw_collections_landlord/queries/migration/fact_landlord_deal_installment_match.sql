WITH originals AS (
    SELECT
        id_invoice,
        id_contract,
        id_account,
        due_amount,
        due_amount_adjustment,
        status,
        payment_status,
        purpose,
        dt_begin,
        dt_due,
        dt_paid,
        dt_end,
        tipo_fat
    FROM
        dw_collections_landlord.fact_invoice_landlord_portfolio AS o
    WHERE
        o.tipo_fat = 'original_invoice'
        AND o.due_amount_adjustment <> 0
        AND o.status = 'written-down'
),
deals AS (
    SELECT
        id_invoice,
        id_contract,
        id_account,
        id_invoice_parent,
        due_amount_adjustment,
        status,
        payment_status,
        purpose,
        dt_begin,
        dt_due,
        dt_paid,
        dt_end,
        tipo_fat
    FROM
        dw_collections_landlord.fact_invoice_landlord_portfolio AS d
    WHERE
        d.tipo_fat <> 'original_invoice'
),
deal_match_pp AS (
    SELECT
        COALESCE(o.id_invoice, o2.id_invoice) AS id_invoice_original,
        d.id_invoice AS id_invoice_deal,
        d.due_amount_adjustment AS due_amount_deal,
        d.status AS status_deal,
        d.payment_status AS payment_status_deal,
        d.purpose AS purpose_deal,
        d.dt_begin AS dt_begin_deal,
        d.dt_due AS dt_due_deal,
        d.dt_paid AS dt_paid_deal,
        d.dt_end AS dt_end_deal,
        CASE
            WHEN o.id_invoice IS NOT NULL THEN 'bill_item_description'
            ELSE 'legacy_fallback'
        END AS match_type
    FROM
        deals AS d
    LEFT JOIN
        originals AS o
        ON d.id_invoice_parent = o.id_invoice
    LEFT JOIN
        originals AS o2
        ON o2.id_contract = d.id_contract
        AND o2.due_amount_adjustment = d.due_amount_adjustment
        AND o2.id_account = d.id_account
        AND o.id_invoice IS NULL
    WHERE
        COALESCE(o.id_invoice, o2.id_invoice) IS NOT NULL
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
        match_type,
        ROW_NUMBER() OVER (
            PARTITION BY id_invoice_original
            ORDER BY
                CASE WHEN match_type = 'bill_item_description' THEN 0 ELSE 1 END,
                id_invoice_deal DESC
        ) AS rn_deal_order
    FROM
        deal_match_pp
)
SELECT
    id_invoice_original,
    id_invoice_deal,
    match_type,
    status_deal,
    payment_status_deal,
    purpose_deal,
    due_amount_deal,
    rn_deal_order,
    dt_begin_deal,
    dt_due_deal,
    dt_paid_deal,
    dt_end_deal
FROM
    order_deal_match
