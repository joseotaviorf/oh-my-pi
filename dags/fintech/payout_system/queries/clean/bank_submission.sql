SELECT
    id,
    batch_id AS id_batch,
    submission_type,
    total_payment_count,
    total_amount,
    total_currency,
    bank_response_status,
    bank_response_body,
    processing_status,
    created_by,
    TIMESTAMP(submitted_at) AS ts_submitted,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_payout_system_raw.bank_submission
