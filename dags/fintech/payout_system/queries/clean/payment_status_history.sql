SELECT
    id,
    payment_request_id AS id_payment_request,
    reason_id AS id_reason,
    correlation_id AS id_correlation,
    previous_status,
    new_status,
    description,
    trace_id,
    raw_payload,
    principal,
    principal_type,
    origin,
    TIMESTAMP(payment_request_created_at) AS ts_payment_request_created,
    TIMESTAMP(status_date) AS ts_status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_payout_system_raw.payment_status_history
