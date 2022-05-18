SELECT
    id,
    installment_id AS id_installment,
    type,
    metadata,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.payment