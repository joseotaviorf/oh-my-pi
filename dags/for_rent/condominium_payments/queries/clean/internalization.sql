SELECT
    CAST(id AS BIGINT) AS id,
    CAST(non_payment_report_invoice_id AS BIGINT) AS id_non_payment_report_invoice,
    due_amount,
    fine_amount,
    already_paid AS is_already_paid,
    TO_TIMESTAMP(accrual_date) AS ts_accrual,
    TO_TIMESTAMP(paid_to_administrator_at) AS ts_paid_to_administrator,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_condominium_payments_raw.internalization
