SELECT
    id,
    installment_id AS id_installment,
    status,
    created_at AS ts_created
FROM
    datalake_lending_raw.installment_status
