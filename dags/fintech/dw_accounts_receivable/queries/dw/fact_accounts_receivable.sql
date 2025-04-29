WITH
base_dim_date AS (
  SELECT DISTINCT
    date,
    is_brz_fintech_business_day,
    next_brz_fintech_business_day
  FROM dw_public.dim_date
  WHERE date >= date('2024-01-01')
    AND date IS NOT NULL
),
city_data AS (
  SELECT DISTINCT
    fhl.sk_contract,
    fhl.sk_region,
    dr.city_name,
    dr.city_group
  FROM dw_rent.fact_house_listings AS fhl
  LEFT JOIN dw_public.dim_region AS dr
    ON fhl.sk_region = dr.sk_region
),
collection_recovery AS (
    SELECT
        id_invoice AS sk_invoice,
        IF(sk_origin_negotiation IS NOT NULL, TRUE, FALSE) AS is_agreement_invoice,
        payment_status,
        net_recovered_amount,
        due_amount,
        paid_amount,
        dt_reference,
        dt_invoice_due_adjust,
        dt_invoice_paid,
        dt_invoice_due,
        dt_month_start,
        dt_month_end
    FROM dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline
    WHERE is_most_recent_record_month IS TRUE
),
calculate_fields AS (
SELECT DISTINCT
    fd.sk_invoice,
    fd.sk_contract,
    fd.closing_month_status,
    fd.invoice_type,
    fd.payment_status,
    i.status AS current_invoice_status,
    cr.payment_status AS overdue_payment_status,
    fd.user AS invoice_account_type,
    CASE
        WHEN cd.city_name IS NULL THEN 'São Paulo'
        ELSE cd.city_name
    END AS city_name,
    CASE
        WHEN cd.city_group IS NULL THEN 'RMSP'
        ELSE cd.city_group
    END AS city_group,
    CASE
        WHEN fd.risk_type = 'LR' THEN 'a.Low_Risk'
        WHEN fd.risk_type = 'HR' THEN 'b.High_Risk'
    END AS risk_group,
    CASE
        WHEN fd.guarantee_type = "FREE" THEN "c.Free"
        WHEN fd.guarantee_type = "PAID" THEN "d.Paid"
    END AS guarantee_group,
    CASE
        WHEN fd.dt_closing between DATE('2021-12-31')
        AND DATE('2022-11-30') AND fd.risk_type = 'LR'
        THEN 'a.Low_Risk'
        WHEN fd.dt_closing between DATE('2021-12-31') AND DATE('2022-11-30')
        AND fd.risk_type = 'HR'
        THEN 'b.High_Risk'
        WHEN fd.dt_closing >= DATE('2022-12-31')
        AND fd.guarantee_type = "FREE"
        THEN 'c.Free'
        WHEN fd.dt_closing >= DATE('2022-12-31')
        AND fd.guarantee_type = "PAID"
        THEN 'd.Paid'
        ELSE ''
    END AS provisional_group,
    fd.delay_contamined_range,
    cr.is_agreement_invoice,
    fd.is_writtendown_in_dead_time,
    CASE
        WHEN i.status <> 'open'
            AND DATE_TRUNC('MONTH',
                COALESCE(i.ts_paid,
                    IF(i.status = 'canceled', i.ts_canceled, NULL))
                ) <= DATE_TRUNC('MONTH', fd.dt_snapshot)
        THEN TRUE
        ELSE FALSE
    END AS is_resolved_next_month,
    CASE
        WHEN fd.dt_closing < fd.dt_due THEN TRUE
        ELSE FALSE
    END AS is_invoice_due,
    fd.due_amount*(-1) AS invoice_amount,
    cr.due_amount,
    cr.paid_amount,
    cr.net_recovered_amount,
    i.paid_amount AS paid_amount_retsuko,
    DATE(i.ts_created) AS dt_created_retsuko,
    i.dt_due_adjusted AS dt_due_adjusted_retsuko,
    cr.dt_reference,
    cr.dt_month_end,
    cr.dt_invoice_due,
    cr.dt_invoice_paid,
    DATE(COALESCE(i.ts_paid, IF(i.status = 'canceled', i.ts_canceled, NULL))) AS dt_paid_retsuko,
    fd.dt_created,
    fd.dt_due,
    IF(dd.is_brz_fintech_business_day, DATE(fd.dt_due), dd.next_brz_fintech_business_day) AS dt_due_adjs,
    fd.dt_paid,
    fd.dt_contract_signature,
    fd.dt_annulment,
    fd.dt_closing,
    fd.dt_snapshot,
    DATE(DATE_TRUNC('MONTH', fd.dt_closing)) + INTERVAL '1' MONTH AS dt_month_recovery -- safra_recuperacao
FROM dw_losses.fact_delay AS fd
LEFT JOIN datalake_retsuko.invoice AS i
    ON fd.sk_invoice = i.id_external
LEFT JOIN collection_recovery AS cr
    ON fd.sk_invoice = cr.sk_invoice
    AND DATE_TRUNC('MONTH', fd.dt_closing) + INTERVAL '1' MONTH = DATE_TRUNC('MONTH', cr.dt_month_end)
LEFT JOIN base_dim_date AS dd
    ON fd.dt_due = dd.DATE
LEFT JOIN city_data AS cd
    ON fd.sk_contract = cd.sk_contract
WHERE
    fd.due_amount < 0
    AND fd.payment_status <> 'canceled'
    AND fd.is_writtendown_in_dead_time IS FALSE
    AND fd.is_international IS FALSE
    AND fd.is_before_started IS FALSE
    AND (
        (DATE_TRUNC('MONTH', fd.dt_closing) < DATE('2024-02-01') AND fd.has_repair_offboarding_bill_item IS NOT NULL)
        OR (DATE_TRUNC('MONTH', fd.dt_closing) >= DATE('2024-02-01') AND fd.has_repair_offboarding_bill_item IS FALSE)
        )
),
calculate_net_recovered AS (
    SELECT
        sk_invoice,
        sk_contract,
        closing_month_status,
        current_invoice_status,
        payment_status,
        invoice_type,
        invoice_account_type,
        is_invoice_due,
        is_agreement_invoice,
        CASE
            WHEN current_invoice_status = 'canceled'
                AND is_resolved_next_month = TRUE
            THEN TRUE
            ELSE FALSE
        END AS is_canceled_invoice,
        provisional_group,
        delay_contamined_range,
        CASE
            WHEN overdue_payment_status <> 'open'
                OR overdue_payment_status IS NOT NULL
                THEN DAY(dt_invoice_paid)
            WHEN current_invoice_status <> 'open'
                AND DATE_TRUNC('MONTH', dt_paid_retsuko) = DATE_TRUNC('MONTH', dt_snapshot)
                THEN DAY(dt_paid_retsuko)
            WHEN current_invoice_status <> 'open'
                AND DATE_TRUNC('MONTH',dt_paid_retsuko) < DATE_TRUNC('MONTH', dt_snapshot)
                THEN 1
            ELSE 0
        END AS day_resolution,
        invoice_amount,
        CASE
            WHEN dt_paid_retsuko <= dt_due_adjs
                OR (current_invoice_status = 'canceled'
                    AND is_resolved_next_month = TRUE)
            THEN invoice_amount
            ELSE net_recovered_amount
        END AS net_recovered,
        dt_contract_signature,
        dt_annulment,
        dt_created,
        dt_due,
        dt_due_adjs,
        dt_paid_retsuko,
        dt_month_recovery,
        dt_closing
    FROM calculate_fields
)
SELECT
    sk_invoice,
    sk_contract,
    closing_month_status,
    current_invoice_status,
    payment_status,
    invoice_type,
    invoice_account_type,
    is_invoice_due,
    is_agreement_invoice,
    is_canceled_invoice,
    provisional_group,
    delay_contamined_range,
    day_resolution,
    invoice_amount,
    CASE
      WHEN day_resolution = 0 THEN 0
      WHEN net_recovered IS NULL THEN 0
      ELSE net_recovered
    END AS net_recovered,
    dt_contract_signature,
    dt_annulment,
    dt_created,
    dt_due,
    dt_due_adjs,
    dt_paid_retsuko,
    dt_month_recovery,
    dt_closing,
    NOW() AS ts_load
FROM calculate_net_recovered
