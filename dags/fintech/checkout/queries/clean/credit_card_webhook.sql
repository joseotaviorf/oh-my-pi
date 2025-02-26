SELECT
    id,
    credit_card_id AS id_credit_card,
    status,
    error_message,
    payload,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_raw.credit_card_webhook
