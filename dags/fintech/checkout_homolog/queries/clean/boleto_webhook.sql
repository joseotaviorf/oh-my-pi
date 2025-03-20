SELECT
    id,
    bolecode_id AS id_bolecode,
    boleto_id AS id_boleto,
    status,
    error_message,
    payload,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_checkout_homolog_raw.boleto_webhook
