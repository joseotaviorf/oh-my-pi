SELECT
    id,
    bolecode_id AS id_bolecode,
    pix_id AS id_pix,
    status,
    error_message,
    payload,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_homolog_raw.pix_webhook
