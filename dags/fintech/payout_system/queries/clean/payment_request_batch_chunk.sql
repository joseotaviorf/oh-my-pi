SELECT
    id,
    batch_id AS id_batch,
    chunk_index,
    status,
    item_count,
    failed_item_count,
    last_error,
    TIMESTAMP(batch_created_at) AS ts_batch_created,
    TIMESTAMP(locked_until) AS ts_locked_until,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    payments
FROM
    datalake_payout_system_raw.payment_request_batch_chunk
