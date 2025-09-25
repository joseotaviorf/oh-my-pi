SELECT 
    id AS id_transaction, 
    batch_id AS id_batch,
    metadata, 
    reverted_by AS reverted_by, 
    TIMESTAMP(request_time) AS ts_request_time, 
    TIMESTAMP(transaction_time) AS ts_transaction_time, 
    TIMESTAMP(reverted_at) AS ts_reverted_at
FROM 
    datalake_ledger_raw.transaction