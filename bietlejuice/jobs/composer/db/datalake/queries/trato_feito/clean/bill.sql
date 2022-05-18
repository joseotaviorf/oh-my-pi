SELECT
    id,
    external_id AS id_external,
    debtor_id AS id_debtor,
    debtor_external_id AS id_debtor_external,
    status,
    amount,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.bill