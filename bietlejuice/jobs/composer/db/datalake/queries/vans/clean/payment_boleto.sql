select
    id,
    requested_by,
    related_document_type,
    related_document_id as id_related_document,
    related_document_status,
    company_use,
    our_number,
    occurrence_code,
    sha2(payee_name,256) as payee_name,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    status,
    paid_at as dt_paid,
    original_response,
    paid_amount,
    bank_payment_code,
    type,
    style,
    bank_payment_id as id_bank_payment,
    barcode   
from
    datalake_vans_raw.payment_boleto