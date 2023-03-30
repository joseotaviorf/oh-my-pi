WITH target_invoices AS (
    SELECT
        fie.id_contract,
        fie.id_invoice,
        c.dt_started AS dt_start,
        c.dt_termination AS dt_annulment,
        c.contract_version AS version,
        c.guarantee_type AS guarantee,
        CASE
          WHEN guarantee_type = 'RentalDeposit' then 'Paid'
          WHEN guarantee_type = 'RentalGuarantee' then 'Paid'
          WHEN guarantee_type = 'PRO_GUARANTOR' then 'Paid'
          WHEN guarantee_type = 'Standalone' then 'Brokerage Only'
          WHEN guarantee_type = 'SeguroFairfax' then 'Free'
          ELSE 'Free'
        END as contract_guarantee_type,
        c.paying_condo AS condo_payer,
        CAST(p.income AS INTEGER) AS monthly_income_declared,
        CAST(p.package AS INTEGER) AS package_amount,
        p.dti,
        r.city_name,
        r.short_region_name,
        r.city_group,
        di.invoice_frequency AS invoice_type,
        di.payment_status,
        di.negotiation_status,
        di.invoice_user AS user,
        i.due_amount,
        i.paid_amount,
        i.ts_created,
        DATE(i.ts_due) AS dt_due,
        CASE
            WHEN dd.week_day = 0 THEN (DATE(i.ts_due) + interval '1' day) -- sunday
            WHEN dd.week_day = 6 THEN (DATE(i.ts_due) + interval '2' day) -- saturday
            WHEN dd.week_day BETWEEN 1
                AND 4
                AND dd.is_brz_holiday = 'Holiday' THEN (DATE(i.ts_due) + interval '1' day)
            WHEN dd.week_day = 5
                AND dd.is_brz_holiday = 'Holiday' THEN (DATE(i.ts_due) + interval '3' day)
            ELSE DATE(i.ts_due)
        END AS dt_due_ajust,
        DATE(i.ts_paid) AS dt_paid,
        ARRAY_JOIN(collect_set(CONCAT(die.entry_type, ': ', ROUND(brl_entry_due_amount,2))), ', ') AS bill_items
    FROM
    datalake_invoice.invoice_entries AS fie
    INNER JOIN datalake_retsuko.invoice_entry AS die
        ON die.id = fie.id
    LEFT JOIN datalake_retsuko.invoice_info AS di
        ON di.id_invoice = fie.id_invoice
    LEFT JOIN datalake_retsuko.invoice AS i
        ON i.id_external = di.id_invoice
    LEFT JOIN datalake_ebdb_contract.contract AS c
        ON c.id = fie.id_contract
    LEFT JOIN datalake_quintoandar.aux_date AS dd
        ON dd.date = DATE(i.ts_due)
    LEFT JOIN datalake_region.region AS r
        ON r.id = fie.id_region
    LEFT JOIN datalake_proposal.proposal AS p
        ON p.id = c.id_proposal
    WHERE
        payment_status != 'canceled'
        AND
            c.country_code = 'BR' -- only quintoandar is in BR for now
        AND
            i.due_amount < 0 -- paid invoices
        AND
            invoice_user = 'tenant' -- only tenants are charged
        AND
            c.status != 'Cancelado' -- only active or finalized
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24
),

invoices_timeline AS (
  SELECT DISTINCT
        dd.month_start,
        dd.month_end,
        dd.week_start,
        dd.week_end,
        dd.date AS reference_date,
        dd.is_brz_holiday,
        CASE
            WHEN working_days_in_month = 0 THEN 1
            ELSE working_days_in_month
        END AS du,
        i.*,
        round(months_between(dd.date, dt_start),0) AS contract_age,
        CASE WHEN i.dt_annulment IS NULL
            OR i.dt_annulment > dd.date THEN 'Active'
            ELSE 'Finished'
        END AS contract_status
    FROM
        datalake_quintoandar.aux_date AS dd
    LEFT JOIN
        target_invoices AS i
            ON i.dt_due_ajust <= dd.month_end
            AND i.dt_due_ajust < dd.date
            AND (i.dt_paid IS NULL
                OR (i.dt_paid >= dd.month_start
                AND i.dt_paid > i.dt_due_ajust)) -- it's only entered into collections portfolio
    WHERE
        DATE BETWEEN date_trunc('month', current_date - interval '24' month)
        AND current_date - interval '1' day
),

tainted_delay AS ( -- sum all contract debts and place at the earliest due_date
    SELECT
        month_end,
        du,
        reference_date,
        id_contract,
        user,
        count(distinct case when dt_due_ajust < reference_date AND (dt_paid > reference_date OR dt_paid is null) then id_invoice end) AS contract_overdue_invoices,
        sum(case when dt_due_ajust < reference_date AND (dt_paid > reference_date OR dt_paid is null) then due_amount*-1 end) AS contract_debt,
        min(dt_due_ajust) AS contract_due_date_min
    FROM
        invoices_timeline
    GROUP BY
        1,2,3,4,5
),

tainted_dataset as (
    SELECT
        it.*,
        datediff(day, it.dt_due_ajust, it.reference_date) AS delay_invoice_at_reference,
        CASE
            WHEN it.dt_due_ajust <= it.month_end
                AND it.dt_paid IS NULL THEN datediff(day, it.dt_due_ajust, it.month_end)
            WHEN it.dt_due_ajust <= it.month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid > it.month_end THEN datediff(day, it.dt_due_ajust, it.month_end)
            WHEN it.dt_due_ajust <= it.month_end
                AND it.dt_paid IS NOT NULL
                AND it.dt_paid <= it.month_end THEN datediff(day, it.dt_due_ajust, it.dt_paid)
            ELSE NULL
        END AS delay_invoice_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.month_start
                AND (it.dt_paid IS NULL
                    OR it.dt_paid > it.month_end) THEN datediff(day, td.contract_due_date_min, it.month_end)
            WHEN td.contract_due_date_min >= it.month_start
                AND it.dt_paid <= it.month_end THEN datediff(day, td.contract_due_date_min, it.dt_paid)
            WHEN td.contract_due_date_min < it.month_start THEN datediff(day, td.contract_due_date_min, it.month_start)
            ELSE NULL
        END AS delay_contamined_at_closure,
        CASE
            WHEN td.contract_due_date_min >= it.month_start THEN 'Flow'
            ELSE 'Stock'
        END AS debtor_type,
        td.contract_due_date_min,
        td.contract_debt,
        td.contract_overdue_invoices
    FROM
        invoices_timeline AS it
    LEFT JOIN
        tainted_delay AS td
            ON it.id_contract = td.id_contract
            AND it.user = td.user
            AND it.month_end = td.month_end
            AND it.du = td.du
            AND it.reference_date = td.reference_date
),

tainted_dataset_range AS (
    SELECT
        *,
        CASE
            WHEN delay_contamined_at_closure IS NULL THEN NULL
            WHEN delay_contamined_at_closure <= 0   THEN 'Current'
            WHEN delay_contamined_at_closure <= 30  THEN '1-30'
            WHEN delay_contamined_at_closure <= 60  THEN '31-60'
            WHEN delay_contamined_at_closure <= 90  THEN '61-90'
            WHEN delay_contamined_at_closure <= 180 THEN '91-180'
            ELSE 'over 180'
        END AS delay_contamined_range
    FROM
        tainted_dataset
    WHERE
        delay_contamined_at_closure > 0
)

SELECT
    id_contract,
    id_invoice,
    contract_status,
    version AS contract_version,
    guarantee AS contract_guarantee,
    contract_guarantee_type,
    contract_age,
    condo_payer,
    city_name,
    short_region_name,
    city_group,
    invoice_type,
    user,
    bill_items,
    payment_status,
    debtor_type,
    monthly_income_declared,
    package_amount,
    dti,
    due_amount,
    paid_amount,
    contract_overdue_invoices,
    contract_debt,
    delay_invoice_at_reference,
    delay_invoice_at_closure,
    delay_contamined_at_closure,
    delay_contamined_range,
    du AS business_day,
    ts_created AS ts_invoice_created,
    contract_due_date_min AS dt_contract_due_date_min,
    dt_start AS dt_contract_started,
    dt_annulment AS dt_contract_annulled,
    dt_due AS dt_invoice_due,
    dt_due_ajust AS dt_invoice_due_adjust,
    dt_paid AS dt_invoice_paid,
    month_start AS dt_month_start,
    month_end AS dt_month_end,
    week_start AS dt_week_start,
    week_end AS dt_week_end,
    reference_date AS dt_reference
FROM tainted_dataset_range
