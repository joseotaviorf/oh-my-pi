SELECT
    id,
    installment_id AS id_installment,
    status,
    payment_source,
    payment_reason,
    created_at AS ts_created
FROM
    datalake_lending_raw.installment_status
