WITH
collection_recovery AS (
    SELECT
        id_invoice,
        net_recovered_amount,
        dt_invoice_due_adjust,
        dt_invoice_paid,
        dt_month_start
    FROM dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline
    WHERE is_most_recent_record_month IS TRUE
    QUALIFY row_number() OVER(PARTITION BY id_invoice, dt_month_end ORDER BY net_recovered_amount DESC) = 1
),
other_recovery AS (
    SELECT
        id_external AS id_invoice,
        status,
        due_amount*-1 AS net_recovered_amount,
        dt_due_adjusted AS dt_invoice_due_adjust,
        COALESCE(DATE(ts_paid), DATE(ts_canceled)) AS dt_invoice_paid,
        DATE_TRUNC('MONTH', COALESCE(DATE(ts_paid), DATE(ts_canceled))) AS dt_month_start
    FROM datalake_retsuko.invoice
    WHERE status <> 'open'
)
SELECT
    l.sk_invoice,
    l.sk_contract,
    l.contract_closing_month_status AS closing_month_status,
    l.provisional_group,
    l.delay_contaminated_range,
    l.due_amount,
    CASE
        WHEN status <> 'open'
            AND od.id_invoice IS NOT NULL
            AND cr.net_recovered_amount IS NULL
        THEN l.due_amount
        ELSE cr.net_recovered_amount
    END AS recovered_amount,
    CASE
        WHEN status <> 'open'
            AND od.id_invoice IS NOT NULL
            AND cr.net_recovered_amount IS NULL
        THEN od.dt_invoice_paid
        ELSE cr.dt_invoice_paid
    END AS dt_invoice_paid,
    DATE(DATE_TRUNC('MONTH', l.dt_closing + INTERVAL '1' MONTH)) AS dt_month
FROM
    dw_losses.fact_losses l
LEFT JOIN
    collection_recovery cr
    ON l.sk_invoice = cr.id_invoice
       AND l.dt_closing = DATE_ADD(cr.dt_month_start, -1)
LEFT JOIN other_recovery od
    ON l.sk_invoice = od.id_invoice
        AND DATE_ADD(od.dt_month_start, -1) <= l.dt_closing
WHERE NOT(l.payment_status = 'paid' AND l.due_amount = 0)
