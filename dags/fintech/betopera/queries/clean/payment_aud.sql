SELECT
    id,
    certificate_id AS id_certificate,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    process_info,
    amount,
    status,
    certificate_id_mod AS mod_id_certificate,
    created_at_mod AS mod_created_at,
    updated_at_mod AS mod_updated_at,
    installment_start_date_mod AS mod_dt_start_installment,
    installment_end_date_mod AS mod_dt_end_installment,
    amount_mod AS mod_amount,
    status_mod AS mod_status,
    process_info_mod AS mod_process_info,
    DATE(installment_start_date) AS dt_start_installment,
    DATE(installment_end_date) AS dt_end_installment,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.payment_aud
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
