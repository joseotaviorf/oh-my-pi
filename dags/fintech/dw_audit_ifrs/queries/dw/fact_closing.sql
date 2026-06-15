WITH base_full AS (
    SELECT
        id_invoice AS sk_invoice,
        id_contract AS sk_contract,
        accrual_year_month,
        closing_month_status,
        city,
        contract_guarantee,
        due_amount,
        invoice_type,
        paid_amount AS invoice_paid_amount,
        is_before_started,
        is_before_started_raw,
        is_canceled_in_dead_time,
        is_guarantee_paid,
        is_international,
        is_paid_in_closing_day,
        is_writtendown_in_dead_time,
        is_write_off,
        is_contract_write_off,
        has_repair_offboarding_bill_item,
        payment_status,
        origin_factor,
        dt_created,
        dt_canceled,
        dt_annulment,
        dt_closing,
        dt_contract_signature,
        dt_due,
        dt_due_adjusted_retsuko,
        dt_paid,
        dt_sent,
        dt_write_off,
        dt_snapshot,
        TRUE AS is_early_bird
    FROM
        dw_audit_ifrs.fact_early_bird_full
    WHERE
        closing_month_status <> 'Finalizado'

    UNION ALL

    SELECT
        sk_invoice,
        sk_contract,
        accrual_year_month,
        closing_month_status,
        city,
        contract_guarantee,
        due_amount,
        invoice_type,
        invoice_paid_amount,
        is_before_started,
        is_before_started_raw,
        is_canceled_in_dead_time,
        is_guarantee_paid,
        is_international,
        is_paid_in_closing_day,
        is_writtendown_in_dead_time,
        is_write_off,
        is_contract_write_off,
        has_repair_offboarding_bill_item,
        payment_status,
        origin_factor,
        dt_created,
        dt_canceled,
        dt_annulment,
        dt_closing,
        dt_contract_signature,
        dt_due,
        dt_due_adjusted_retsuko,
        dt_paid,
        dt_sent,
        dt_write_off,
        dt_snapshot,
        FALSE AS is_early_bird
    FROM
        dw_losses.fact_closing
    WHERE
        (
            (
                DATE_TRUNC('month', dt_closing) <> DATE('2023-01-01')
                AND is_paid_in_closing_day = FALSE
            )
            OR (
                DATE_TRUNC('month', dt_closing) = DATE('2023-01-01')
                AND (is_paid_in_closing_day = TRUE OR is_paid_in_closing_day = FALSE)
            )
        )
        AND (
            (
                DATE_TRUNC('month', dt_closing) < DATE('2024-02-01')
                AND (has_repair_offboarding_bill_item = TRUE OR has_repair_offboarding_bill_item = FALSE)
            )
            OR (
                DATE_TRUNC('month', dt_closing) >= DATE('2024-02-01')
                AND has_repair_offboarding_bill_item = FALSE
            )
        )
)
SELECT
    base_full.dt_closing,
    base_full.sk_contract,
    base_full.sk_invoice,
    base_full.invoice_type,
    prov.invoice_status,
    base_full.payment_status,
    delay.user AS invoice_account_type,
    base_full.dt_due,
    base_full.dt_paid,
    base_full.is_writtendown_in_dead_time,
    CASE
        WHEN base_full.is_guarantee_paid IS TRUE THEN 'b. Paid'
        ELSE 'a. Free'
    END AS provisional_group,
    base_full.is_international,
    base_full.is_before_started,
    base_full.has_repair_offboarding_bill_item,
    bih.invoice_hierarchy,
    base_full.is_early_bird,
    base_full.is_write_off,
    base_full.dt_write_off,
    base_full.closing_month_status,
    dr.bigger_anchor_deal_at_contract,
    dr.delta_days,
    dr.is_contract_with_deal,
    dr.delay_at_deal_creation,
    dr.deal_status,
    delay.delay_contamined_range,
    delay.delay_contaminated_range_rule_e,
    CAST(-1 * base_full.due_amount AS DECIMAL(32, 2)) AS due_amount,
    CAST(-1 * prov.provision_balance AS DECIMAL(32, 2)) AS provision_balance
FROM
    base_full
LEFT JOIN
    dw_losses.fact_provision AS prov
        ON prov.sk_invoice = base_full.sk_invoice
        AND prov.dt_closing = base_full.dt_closing
LEFT JOIN
    dw_losses.fact_delay AS delay
        ON delay.sk_invoice = prov.sk_invoice
        AND delay.dt_closing = prov.dt_closing
LEFT JOIN
    dw_audit_ifrs.fact_delay_rule AS dr
        ON dr.id_invoice = base_full.sk_invoice
        AND dr.dt_closing = base_full.dt_closing
LEFT JOIN
    dw_audit_ifrs.dim_bill_item_hierarchy AS bih
        ON bih.sk_invoice = base_full.sk_invoice
WHERE
    base_full.due_amount < 0
    AND base_full.payment_status <> 'canceled'
    AND COALESCE(base_full.is_writtendown_in_dead_time, FALSE) = FALSE
    AND (base_full.is_international = FALSE OR base_full.is_international IS NULL)
    AND (base_full.is_before_started = FALSE OR base_full.is_before_started IS NULL)
    AND (prov.invoice_status <> 'Baixado' OR prov.invoice_status IS NULL)
GROUP BY
    base_full.dt_closing,
    base_full.sk_contract,
    base_full.sk_invoice,
    base_full.invoice_type,
    prov.invoice_status,
    base_full.payment_status,
    delay.user,
    base_full.dt_due,
    base_full.dt_paid,
    base_full.is_writtendown_in_dead_time,
    base_full.is_guarantee_paid,
    base_full.is_international,
    base_full.is_before_started,
    base_full.has_repair_offboarding_bill_item,
    bih.invoice_hierarchy,
    base_full.is_early_bird,
    base_full.is_write_off,
    base_full.dt_write_off,
    base_full.closing_month_status,
    dr.bigger_anchor_deal_at_contract,
    dr.delta_days,
    dr.is_contract_with_deal,
    dr.delay_at_deal_creation,
    dr.deal_status,
    delay.delay_contamined_range,
    delay.delay_contaminated_range_rule_e,
    base_full.due_amount,
    prov.provision_balance
