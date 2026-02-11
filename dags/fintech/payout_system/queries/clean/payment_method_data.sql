SELECT
    id,
    payment_request_id AS id_payment_request,
    method_data,
    TIMESTAMP(payment_request_created_at) AS ts_payment_request_created,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_payout_system_raw.payment_method_data
