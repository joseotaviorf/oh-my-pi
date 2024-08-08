SELECT
    id,
    account_id AS id_account,
    external_id AS id_external,
    transaction_id AS id_transaction,
    bank_payment_id AS id_bank_payment,
    pix_link,
    emv AS pix_emv,
    amount,
    bank_fee,
    status,
    DATE(date_limit) AS dt_limit,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_pixar_raw.charge
