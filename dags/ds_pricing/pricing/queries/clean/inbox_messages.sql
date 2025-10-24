SELECT
    message_id AS id_message,
    queue_name,
    message_type,
    message_body,
    status,
    retry_count,
    max_retries,
    created_at AS ts_created,
    processed_at AS ts_processed,
    error_message
FROM
    datalake_pricing_raw.inbox_messages

