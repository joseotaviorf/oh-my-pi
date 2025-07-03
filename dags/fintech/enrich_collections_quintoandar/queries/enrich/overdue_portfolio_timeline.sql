WITH
target_invoices AS (
    SELECT DISTINCT
        i.id_contract,
        p.id AS id_proposal,
        i.id_invoice,
        i.id_negotiation_child,
        i.id_negotiation_parent,
        i.negotiation_installment_number,
        i.recovery_channel,
        eh.id_region,
        i.user,
        i.purpose AS invoice_type,
        i.invoice_status,
        i.substatus,
        i.reason,
        i.paid_via,
        i.is_write_off,
        i.is_contract_write_off,
        i.is_first_payment AS is_first_payment_default,
        i.has_app_action_event,
        i.due_amount,
        i.paid_amount,
        i.contract_status,
        DATE(i.ts_due) AS dt_due,
        DATE(i.ts_paid) AS dt_paid,
        DATE(i.ts_write_off) AS dt_write_off,
        i.dt_due_adjusted,
        i.dt_contract_annulled,
        GREATEST(
            DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH),
            DATE_ADD(i.dt_due_adjusted, 1)) AS dt_start_interval,
        CASE
            WHEN DATE(i.ts_paid) IS NOT NULL AND DATE(i.ts_paid) < DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH) THEN NULL
            WHEN DATE(i.ts_paid) IS NOT NULL AND DATE(i.ts_paid) > CURRENT_DATE THEN NULL
            WHEN DATE(i.ts_paid) IS NOT NULL THEN LAST_DAY(DATE(i.ts_paid))
            ELSE CURRENT_DATE
        END AS dt_end_interval
    FROM datalake_collections_quintoandar.invoice_portfolio AS i
    LEFT JOIN datalake_ebdb_clean.house AS eh
        ON i.id_house = eh.id
    LEFT JOIN datalake_proposal.proposal AS p
        ON p.id = i.id_proposal
    WHERE
        (LOWER(i.invoice_status) != "canceled"
            AND LOWER(i.contract_status) != "cancelado")
        AND ((DATE(i.ts_paid) IS NULL OR DATE(i.ts_paid) > i.dt_due_adjusted)
            AND DATE_ADD(i.dt_due_adjusted, 1) <= CURRENT_DATE)
),
explode_invoices_dates AS (
    SELECT
        *,
        EXPLODE(
            SEQUENCE(
                dt_start_interval,
                GREATEST(dt_start_interval, IF(dt_end_interval = LAST_DAY(CURRENT_DATE), CURRENT_DATE, dt_end_interval))
            )
        ) AS ts_reference
    FROM
        target_invoices
    WHERE
        dt_end_interval IS NOT NULL
        AND dt_start_interval <= dt_end_interval
),
invoices_timeline AS (
  SELECT DISTINCT
        i.id_contract,
        i.id_proposal,
        i.id_invoice,
        i.id_region,
        i.id_negotiation_child,
        i.id_negotiation_parent,
        i.negotiation_installment_number,
        i.recovery_channel,
        i.user,
        i.invoice_type,
        CASE
            WHEN i.invoice_status = "not-payable" THEN "not-payable"
            WHEN i.invoice_status = "divergent-payment" THEN "divergent-payment"
            WHEN DATE(i.ts_reference) >= dt_paid
                AND i.invoice_status = "written-down" THEN "written-down"
            WHEN DATE(i.ts_reference) >= dt_paid THEN "paid"
            ELSE "open"
        END AS payment_status,
        i.substatus,
        i.reason,
        i.paid_via,
        CASE
            WHEN dd.working_days_in_month_fintech = 0 THEN 1
            ELSE dd.working_days_in_month_fintech
        END AS business_day,
        i.is_write_off,
        i.is_contract_write_off,
        i.is_first_payment_default,
        i.has_app_action_event,
        CASE
            WHEN DATE(i.ts_reference) < i.dt_contract_annulled THEN "Active"
            WHEN DATE(i.ts_reference) >= i.dt_contract_annulled THEN "Finished"
            WHEN contract_status = "Ativo" THEN "Active"
            WHEN contract_status = "Finalizado" THEN "Finished"
            ELSE contract_status
        END AS contract_status,
        i.due_amount,
        i.paid_amount,
        i.dt_due,
        i.dt_due_adjusted,
        i.dt_paid,
        i.dt_contract_annulled,
        i.dt_write_off,
        DATE(i.ts_reference) AS dt_reference,
        dd.month_start AS dt_month_start,
        dd.month_end AS dt_month_end
    FROM explode_invoices_dates AS i
    LEFT JOIN datalake_quintoandar.aux_date AS dd
        ON DATE(i.ts_reference) = dd.date
),
tainted_delay AS (
    SELECT
        dt_month_end,
        business_day,
        dt_reference,
        id_contract,
        COUNT(DISTINCT CASE WHEN dt_due_adjusted < dt_reference AND (dt_paid > dt_reference OR dt_paid IS NULL) THEN id_invoice END) AS contract_overdue_invoices,
        SUM(CASE WHEN dt_due_adjusted < dt_reference AND (dt_paid > dt_reference OR dt_paid IS NULL) THEN due_amount*-1 END) AS contract_debt,
        MIN(dt_due_adjusted) AS contract_due_date_min
    FROM
        invoices_timeline
    GROUP BY
        1,2,3,4
),
tainted_dataset as (
    SELECT
        it.*,
        CASE
            WHEN it.dt_paid BETWEEN it.dt_month_start AND it.dt_reference
                AND it.dt_paid > it.dt_due_adjusted
            THEN it.dt_paid
        END AS dt_paid_timeline,
        DATEDIFF(DAY, it.dt_due_adjusted,
            CASE
                WHEN it.dt_paid BETWEEN it.dt_month_start AND it.dt_reference
                    AND it.dt_paid > it.dt_due_adjusted
                THEN it.dt_paid
        END) AS delay_invoice_at_payment,
        DATEDIFF(DAY, it.dt_due_adjusted, it.dt_reference) AS delay_invoice_at_reference,
        CASE
            WHEN it.dt_due_adjusted <= it.dt_month_end
                AND it.dt_paid IS NULL THEN DATEDIFF(DAY, it.dt_due_adjusted, it.dt_month_end)
            WHEN it.dt_due_adjusted <= it.dt_month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid > it.dt_month_end THEN DATEDIFF(DAY, it.dt_due_adjusted, it.dt_month_end)
            WHEN it.dt_due_adjusted <= it.dt_month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid <= it.dt_month_end THEN DATEDIFF(DAY, it.dt_due_adjusted, it.dt_paid)
            ELSE NULL
        END AS delay_invoice_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.dt_month_start
                AND (it.dt_paid IS NULL
                    OR it.dt_paid > it.dt_month_end) THEN DATEDIFF(DAY, td.contract_due_date_min, it.dt_month_end)
            WHEN td.contract_due_date_min >= it.dt_month_start
                AND it.dt_paid <= it.dt_month_end THEN DATEDIFF(DAY, td.contract_due_date_min, it.dt_paid)
            WHEN td.contract_due_date_min < it.dt_month_start THEN DATEDIFF(DAY, td.contract_due_date_min, it.dt_month_start)
            ELSE NULL
        END AS delay_contamined_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.dt_month_start THEN "Flow"
            ELSE "Stock"
        END AS debtor_type,
        td.contract_due_date_min,
        td.contract_debt,
        td.contract_overdue_invoices
    FROM
        invoices_timeline AS it
    LEFT JOIN
        tainted_delay AS td
            ON it.id_contract = td.id_contract
            AND it.dt_month_end = td.dt_month_end
            AND it.business_day = td.business_day
            AND it.dt_reference = td.dt_reference
),

tainted_dataset_range AS (
    SELECT
        *,
        MAX(dt_reference) OVER(PARTITION BY id_invoice, dt_month_end, business_day) AS max_date_between_business_days,
        CASE
            WHEN delay_contamined_at_closure IS NULL THEN NULL
            WHEN delay_contamined_at_closure <= 0   THEN "Current"
            WHEN delay_contamined_at_closure <= 30  THEN "1-30"
            WHEN delay_contamined_at_closure <= 60  THEN "31-60"
            WHEN delay_contamined_at_closure <= 90  THEN "61-90"
            WHEN delay_contamined_at_closure <= 120 THEN "91-120"
            WHEN delay_contamined_at_closure <= 150 THEN "121-150"
            WHEN delay_contamined_at_closure <= 180 THEN "151-180"
            WHEN delay_contamined_at_closure <= 360 THEN "181-360"
            WHEN delay_contamined_at_closure <= 540 THEN "361-540"
            WHEN delay_contamined_at_closure <= 720 THEN "541-720"
            WHEN delay_contamined_at_closure <= 1080 THEN "721-1080"
            ELSE "over 1080"
        END AS delay_contamined_range,
        CASE
            WHEN delay_contamined_at_closure IS NULL THEN NULL
            WHEN delay_contamined_at_closure <= 0   THEN "a. Current"
            WHEN delay_contamined_at_closure <= 30  THEN "b. 1-30"
            WHEN delay_contamined_at_closure <= 60  THEN "c. 31-60"
            WHEN delay_contamined_at_closure <= 90  THEN "d. 61-90"
            WHEN delay_contamined_at_closure <= 120 THEN "e. 91-120"
            WHEN delay_contamined_at_closure <= 150 THEN "f. 121-150"
            WHEN delay_contamined_at_closure <= 180 THEN "g. 151-180"
            ELSE "h. over 180"
        END AS delay_contract_range,
        CASE
            WHEN COALESCE(delay_invoice_at_payment, delay_invoice_at_reference) IS NULL THEN NULL
            WHEN COALESCE(delay_invoice_at_payment, delay_invoice_at_reference) < 7 THEN 0
            WHEN COALESCE(delay_invoice_at_payment, delay_invoice_at_reference) < 15 THEN 7
            WHEN COALESCE(delay_invoice_at_payment, delay_invoice_at_reference) < 30 THEN 15
            WHEN COALESCE(delay_invoice_at_payment, delay_invoice_at_reference) < 60 THEN 30
            ELSE 60
        END AS delay_first_payment_default
    FROM
        tainted_dataset
    WHERE
        delay_contamined_at_closure > 0
)
SELECT
    id_contract,
    id_proposal,
    id_invoice,
    id_region,
    id_negotiation_child,
    id_negotiation_parent,
    negotiation_installment_number,
    recovery_channel,
    contract_status,
    user,
    invoice_type,
    payment_status,
    substatus,
    reason,
    CASE
        WHEN dt_paid BETWEEN dt_month_start AND dt_reference
            AND dt_paid > dt_due_adjusted
        THEN paid_via
    END AS paid_via,
    CASE
        WHEN dt_reference >= dt_write_off THEN is_write_off
    END AS is_write_off,
    is_contract_write_off,
    is_first_payment_default,
    delay_first_payment_default,
    debtor_type,
    due_amount,
    CASE
        WHEN dt_paid BETWEEN dt_month_start AND dt_reference
            AND dt_paid > dt_due_adjusted
        THEN paid_amount
    END AS paid_amount,
    CASE
        WHEN dt_paid BETWEEN dt_month_start AND dt_reference
            AND dt_paid > dt_due_adjusted
        THEN due_amount
    END AS recovered_amount,
    contract_overdue_invoices,
    contract_debt,
    delay_invoice_at_reference,
    delay_invoice_at_closure,
    delay_contamined_at_closure,
    delay_contamined_range,
    delay_contract_range,
    business_day,
    IF(dt_reference = max_date_between_business_days, TRUE, FALSE) AS is_last_business_days,
    has_app_action_event,
    dt_contract_annulled,
    contract_due_date_min AS dt_contract_due_date_min,
    dt_paid_timeline AS dt_invoice_paid,
    dt_due AS dt_invoice_due,
    dt_due_adjusted AS dt_invoice_due_adjust,
    CASE
        WHEN dt_reference >= dt_write_off THEN dt_write_off
    END AS dt_write_off,
    dt_month_start,
    dt_month_end,
    dt_reference AS dt_reference,
    NOW() AS ts_load
FROM
    tainted_dataset_range
