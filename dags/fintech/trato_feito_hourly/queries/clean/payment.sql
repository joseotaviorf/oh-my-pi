SELECT
    id,
    installment_id AS id_installment,
    installment_external_id AS id_installment_external,
    type,
    metadata,
    status,
    paid_at AS dt_paid,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_hourly_raw.payment
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
