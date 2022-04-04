SELECT
    id_late_payments AS sk_late_payments,
    id_contract,
    type_late,
    invoice_theorical_amount,
    invoice_paid_amount,
    accrual_year_month,
    dt_created,
    dt_due,
    dt_paid
FROM
    datalake_revenue_lines.late_payments