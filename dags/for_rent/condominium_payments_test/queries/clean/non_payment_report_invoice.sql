SELECT
    CAST(id AS BIGINT) AS id,
    CAST(non_payment_report_id AS BIGINT) AS id_non_payment_report,
    due_month,
    due_year,
    TO_DATE(invoice_due_date) AS dt_due,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_condominium_payments_test_raw.non_payment_report_invoice
