SELECT
    id,
    collector_id AS id_collector,
    collector_external_id AS id_collector_external,
    debtor_id AS id_debtor,
    debtor_external_id AS id_debtor_external,
    status,
    status_reason,
    payload,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.billing
