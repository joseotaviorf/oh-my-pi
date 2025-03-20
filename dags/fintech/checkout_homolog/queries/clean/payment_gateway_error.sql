SELECT 
    id,
    requester_id AS id_requester,
    original_payload,
    payment_gateway_response,
    payment_gateway,
    payment_method,
    TIMESTAMP(sent_at) AS ts_sent,
    TIMESTAMP(error_at) AS ts_error
FROM 
    datalake_checkout_homolog_raw.payment_gateway_error