SELECT
    id,
    entity_id AS id_entity,
    collector_id AS id_collector,
    entity_type,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.status_sync
