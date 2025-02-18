SELECT
    id,
    bank_payment_id AS id_bank_payment,
    bank_boleto_id AS id_bank_boleto,
    name,
    path,
    type,
    origin,
    timestamp(created_at) AS ts_created,
    timestamp(sent_at) AS ts_sent
FROM
    datalake_vans_raw.file
