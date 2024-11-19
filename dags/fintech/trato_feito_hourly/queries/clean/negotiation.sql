SELECT
    id,
    collector_id AS id_collector,
    collector_external_id AS id_collector_external,
    debtor_id AS id_debtor,
    debtor_external_id AS id_debtor_external,
    status,
    currency,
    status_reason,
    payload,
    manage_type,
    consultancy,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_trato_feito_hourly_raw.negotiation
