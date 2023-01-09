SELECT
    id,
    name,
    path,
    timestamp(created_at) AS ts_created,
    type,
    origin,
    timestamp(sent_at) AS ts_sent,
    bank_payment_id AS id_bank_payment,
    bank_boleto_id AS id_bank_boleto
FROM
    datalake_vans_raw.file
