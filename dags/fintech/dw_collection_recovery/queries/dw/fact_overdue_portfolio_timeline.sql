WITH
ssn_original_payment AS (
    -- Service Self Negotiation where customer paid the original invoice
    SELECT DISTINCT
        event_properties:contract_id AS id_contract,
        event_properties:invoice_id AS id_invoice
    FROM
        datalake_amplitude_clean.170698_pending_invoices_invoice_pay_button_clicked_events
    WHERE
        event_properties:contract_id IS NOT NULL
        AND event_properties:invoice_id IS NOT NULL
),
ssn_boletao AS (
    SELECT DISTINCT
        d.id_external AS id_invoice,
        n.id_contract
    FROM
        datalake_trato_feito_clean.debt AS d
    LEFT JOIN
        datalake_debt_recovery.negotiation AS n
            ON d.id_negotiation = n.id_negotiation
    WHERE n.collector = "5A-collector"
)
SELECT
    CONCAT(o.id_invoice, "-", DATE_FORMAT(dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    o.id_contract,
    o.id_invoice,
    id_proposal,
    contract_status,
    invoice_type,
    payment_status,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND reason NOT IN ("negotiation-recupera", "agreement") AND payment_status = "paid" THEN TRUE
        WHEN bossn.id_invoice IS NOT NULL AND payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND reason NOT IN ("negotiation-recupera", "agreement") AND payment_status = "paid" THEN "POSSN (payment of original)"
        WHEN bossn.id_invoice IS NOT NULL AND payment_status = "written-down" THEN "BOSSN (single debt negotiation)"
        ELSE NULL
    END AS type_ssn,
    debtor_type,
    delay_contamined_range,
    contract_overdue_invoices,
    due_amount,
    paid_amount,
    recovered_amount,
    contract_debt,
    business_day,
    is_last_business_days,
    dt_invoice_paid,
    dt_invoice_due,
    dt_invoice_due_adjust,
    dt_month_start,
    dt_month_end,
    dt_reference,
    NOW() AS ts_load
FROM
    datalake_invoice.overdue_portfolio_timeline AS o
LEFT JOIN
    ssn_original_payment AS possn
        ON possn.id_invoice = o.id_invoice
        AND possn.id_contract = o.id_contract
LEFT JOIN ssn_boletao AS bossn
    ON bossn.id_invoice = o.id_invoice
    AND bossn.id_contract = o.id_contract
