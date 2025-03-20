SELECT 
    id,
    pix_id AS id_pix,
    bank_refund_id AS id_bank_refund,
    bank_return_id AS id_bank_return,
    refunded_amount,
    status,
    TIMESTAMP(started_processing_at) AS ts_started_processing, 
    TIMESTAMP(refunded_at) AS ts_created, 
    TIMESTAMP(updated_at) AS ts_updated
FROM 
    datalake_checkout_homolog_raw.pix_refund