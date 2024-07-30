WITH
target_invoices AS (
    SELECT DISTINCT
        i.id_contract_external AS id_contract,
        p.id AS id_proposal,
        i.id_external AS id_invoice,
        ii.invoice_user AS user,
        i.purpose AS invoice_type,
        i.status AS payment_status,
        i.substatus,
        i.reason,
        i.due_amount,
        i.paid_amount,
        c.status AS contract_status,
        DATE(i.ts_due) AS dt_due,
        i.dt_due_adjusted,
        DATE(i.ts_paid) AS dt_paid,
        c.dt_termination AS dt_contract_annulled
    FROM
        datalake_retsuko.invoice AS i
    LEFT JOIN
        datalake_retsuko.invoice_info AS ii
            ON i.id_external = ii.id_invoice
    LEFT JOIN datalake_ebdb_contract.contract AS c
        ON c.id = i.id_contract_external
    LEFT JOIN datalake_proposal.proposal AS p
        ON p.id = c.id_proposal
    WHERE
        LOWER(i.status) != "canceled"
        AND LOWER(c.status) != "cancelado" -- only active or finalized
        AND c.country_code = "BR" -- only quintoandar is in BR for now
        AND ii.invoice_user = "tenant"
        AND i.due_amount < 0 -- paid invoices
),
invoices_timeline AS (
  SELECT DISTINCT
        dd.month_start,
        dd.month_end,
        dd.date AS reference_date,
        CASE
            WHEN dd.working_days_in_month_fintech = 0 THEN 1
            ELSE dd.working_days_in_month_fintech
        END AS business_day,
        i.id_contract,
        i.id_proposal,
        i.id_invoice,
        i.user,
        i.invoice_type,
        CASE
            WHEN i.payment_status = "not-payable" THEN "not-payable"
            WHEN i.payment_status = "divergent-payment" THEN "divergent-payment"
            WHEN dd.date >= dt_paid
                AND i.payment_status = "written-down" THEN "written-down"
            WHEN dd.date >= dt_paid THEN "paid"
            ELSE "open"
        END AS payment_status,
        i.substatus,
        i.reason,
        CASE
            WHEN dd.date < i.dt_contract_annulled THEN "Active"
            WHEN dd.date >= i.dt_contract_annulled THEN "Finished"
            WHEN contract_status = "Ativo" THEN "Active"
            WHEN contract_status = "Finalizado" THEN "Finished"
            ELSE contract_status
        END AS contract_status,
        i.due_amount,
        i.paid_amount,
        i.dt_due,
        i.dt_due_adjusted,
        i.dt_paid,
        i.dt_contract_annulled
    FROM
        datalake_quintoandar.aux_date AS dd
    LEFT JOIN
        target_invoices AS i
            ON i.dt_due_adjusted <= dd.month_end
            AND i.dt_due_adjusted < dd.date
            AND (i.dt_paid IS NULL
                OR (i.dt_paid >= dd.month_start
                AND i.dt_paid > i.dt_due_adjusted)) -- it's only entered into collections portfolio
    WHERE
        dd.date BETWEEN DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH)
        AND CURRENT_DATE - INTERVAL "1" DAY
),
tainted_delay AS ( -- sum all contract debts and place at the earliest due_date
    SELECT
        month_end,
        business_day,
        reference_date,
        id_contract,
        COUNT(DISTINCT CASE WHEN dt_due_adjusted < reference_date AND (dt_paid > reference_date OR dt_paid IS NULL) THEN id_invoice END) AS contract_overdue_invoices,
        SUM(CASE WHEN dt_due_adjusted < reference_date AND (dt_paid > reference_date OR dt_paid IS NULL) THEN due_amount*-1 END) AS contract_debt,
        MIN(dt_due_adjusted) AS contract_due_date_min
    FROM
        invoices_timeline
    GROUP BY
        1,2,3,4
),
tainted_dataset as (
    SELECT
        it.*,
        DATEDIFF(DAY, it.dt_due_adjusted, it.reference_date) AS delay_invoice_at_reference,
        CASE
            WHEN it.dt_due_adjusted <= it.month_end
                AND it.dt_paid IS NULL THEN DATEDIFF(DAY, it.dt_due_adjusted, it.month_end)
            WHEN it.dt_due_adjusted <= it.month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid > it.month_end THEN DATEDIFF(DAY, it.dt_due_adjusted, it.month_end)
            WHEN it.dt_due_adjusted <= it.month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid <= it.month_end THEN DATEDIFF(DAY, it.dt_due_adjusted, it.dt_paid)
            ELSE NULL
        END AS delay_invoice_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.month_start
                AND (it.dt_paid IS NULL
                    OR it.dt_paid > it.month_end) THEN DATEDIFF(DAY, td.contract_due_date_min, it.month_end)
            WHEN td.contract_due_date_min >= it.month_start
                AND it.dt_paid <= it.month_end THEN DATEDIFF(DAY, td.contract_due_date_min, it.dt_paid)
            WHEN td.contract_due_date_min < it.month_start THEN DATEDIFF(DAY, td.contract_due_date_min, it.month_start)
            ELSE NULL
        END AS delay_contamined_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.month_start THEN "Flow"
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
            AND it.month_end = td.month_end
            AND it.business_day = td.business_day
            AND it.reference_date = td.reference_date
),

tainted_dataset_range AS (
    SELECT
        *,
        MAX(reference_date) OVER(PARTITION BY id_invoice, month_end, business_day) AS max_date_between_business_days,
        CASE
            WHEN delay_contamined_at_closure IS NULL THEN NULL
            WHEN delay_contamined_at_closure <= 0   THEN "Current"
            WHEN delay_contamined_at_closure <= 30  THEN "1-30"
            WHEN delay_contamined_at_closure <= 60  THEN "31-60"
            WHEN delay_contamined_at_closure <= 90  THEN "61-90"
            WHEN delay_contamined_at_closure <= 120 THEN "91-120"
            WHEN delay_contamined_at_closure <= 180 THEN "121-180"
            WHEN delay_contamined_at_closure <= 360 THEN "181-360"
            WHEN delay_contamined_at_closure <= 540 THEN "361-540"
            WHEN delay_contamined_at_closure <= 720 THEN "541-720"
            WHEN delay_contamined_at_closure <= 1080 THEN "721-1080"
            ELSE "over 1080"
        END AS delay_contamined_range
    FROM
        tainted_dataset
    WHERE
        delay_contamined_at_closure > 0
)

SELECT
    id_contract,
    id_proposal,
    id_invoice,
    contract_status,
    user,
    invoice_type,
    payment_status,
    substatus,
    reason,
    debtor_type,
    due_amount,
    CASE
        WHEN dt_paid BETWEEN month_start AND reference_date
            AND dt_paid > dt_due_adjusted
        THEN paid_amount
    END AS paid_amount,
    CASE
        WHEN dt_paid BETWEEN month_start AND reference_date
            AND dt_paid > dt_due_adjusted
        THEN due_amount
    END AS recovered_amount,
    contract_overdue_invoices,
    contract_debt,
    delay_invoice_at_reference,
    delay_invoice_at_closure,
    delay_contamined_at_closure,
    delay_contamined_range,
    business_day,
    IF(reference_date=max_date_between_business_days, TRUE, FALSE) AS is_last_business_days,
    dt_contract_annulled,
    contract_due_date_min AS dt_contract_due_date_min,
    CASE
        WHEN dt_paid BETWEEN month_start AND reference_date
            AND dt_paid > dt_due_adjusted
        THEN dt_paid
    END AS dt_invoice_paid,
    dt_due AS dt_invoice_due,
    dt_due_adjusted AS dt_invoice_due_adjust,
    month_start AS dt_month_start,
    month_end AS dt_month_end,
    reference_date AS dt_reference
FROM tainted_dataset_range
