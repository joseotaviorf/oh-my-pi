SELECT
    id,
    sales_flow_id AS id_sales_flow,
    offer_id AS id_offer,
    recipient_type,
    status,
    failure_reason,
    attempt_count,
    expected_invoices_count,
    found_invoices_count,
    last_error_message,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.invoice_tracking

