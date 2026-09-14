SELECT
    id,
    bank_submission_id AS id_bank_submission,
    file_id AS id_file,
    file_name,
    TIMESTAMP(bank_submission_created_at) AS ts_bank_submission_created,
    TIMESTAMP(changed_at) AS ts_changed,
    TIMESTAMP(sent_at) AS ts_sent
FROM
    datalake_payout_system_raw.bank_submission_file
