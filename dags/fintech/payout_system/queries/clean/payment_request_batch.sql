SELECT
    id,
    requester_id AS id_requester,
    idempotency_key_id AS id_idempotency_key,
    bank_submission_id AS id_bank_submission,
    status,
    total_payments,
    total_chunks,
    processed_chunks,
    TIMESTAMP(bank_submission_created_at) AS ts_bank_submission_created,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_payout_system_raw.payment_request_batch
