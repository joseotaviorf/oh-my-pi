SELECT
    id,
    certificate_id AS id_certificate,
    process_info,
    amount,
    status,
    DATE(installment_start_date) AS dt_start_installment,
    DATE(installment_end_date) AS dt_end_installment,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.payment
