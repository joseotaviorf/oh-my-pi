SELECT
    id,
    installment_id AS id_installment,
    installment_external_id AS id_installment_external,
    type,
    metadata,
    status,
    paid_at AS dt_paid,
    credit_date AS dt_credit,
    created_at AS ts_created,
    updated_at AS ts_updated,
    started_processing_at AS ts_started_processing,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_trato_feito_hourly_raw.payment
