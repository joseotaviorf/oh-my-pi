SELECT
    id,
    requested_by,
    related_document_type,
    related_document_id AS id_related_document,
    related_document_status,
    company_use,
    our_number,
    occurrence_code,
    payee_name,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated,
    status,
    paid_at AS dt_paid,
    original_response,
    paid_amount,
    bank_payment_code,
    type,
    style,
    bank_payment_id AS id_bank_payment,
    barcode
FROM
    datalake_vans_raw.paymentboleto
