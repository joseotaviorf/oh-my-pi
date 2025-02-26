SELECT
    id,
    bolecode_id AS id_bolecode,
    pix_id AS id_pix,
    status,
    message_error,
    payload,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_raw.pix_webhook
