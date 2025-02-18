SELECT
    id,
    bank_payment_id AS id_bank_payment,
    related_document_id AS id_related_document,
    company_use,
    our_number,
    requested_by,
    related_document_type,
    related_document_status,
    occurrence_code,
    occurrence_reason,
    payee_name,
    status,
    original_response,
    paid_amount,
    bank_payment_code,
    type,
    style,
    barcode,
    timestamp(created_at) AS ts_created,
    paid_at AS dt_paid,
    timestamp(updated_at) AS ts_updated
FROM
    datalake_vans_raw.paymentboleto
