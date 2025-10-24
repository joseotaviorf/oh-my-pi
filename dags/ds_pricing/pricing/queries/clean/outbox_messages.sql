SELECT
    message_id AS id_message,
    destination,
    message_body,
    status,
    retry_count,
    max_retries,
    created_at AS ts_created,
    sent_at AS ts_sent,
    error_message
FROM
    datalake_pricing_raw.outbox_messages

