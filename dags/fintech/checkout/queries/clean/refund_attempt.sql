SELECT
    id,
    order_id AS id_order,
    charge_id AS id_charge,
    payment_id AS id_payment,
    refunded_by,
    payment_method,
    reason,
    status,
    error_message,
    refund_amount,
    TIMESTAMP(requested_at) AS ts_requested,
    TIMESTAMP(completed_at) AS ts_completed,
    TIMESTAMP(failed_at) AS ts_failed,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_raw.refund_attempt
