SELECT
    id,
    bank_submission_id AS id_bank_submission,
    payment_request_id AS id_payment_request,
    sequence_number,
    TIMESTAMP(bank_submission_created_at) AS ts_bank_submission_created,
    TIMESTAMP(payment_request_created_at) AS ts_payment_request_created,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_payout_system_raw.bank_submission_item
