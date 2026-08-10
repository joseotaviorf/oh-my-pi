SELECT
    id,
    bill_id AS id_bill,
    unique_id AS id_unique,
    version,
    status,
    event_type,
    request_date AS ts_request,
    response_date AS ts_response,
    callback_date AS ts_callback,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.sap_audit_response
