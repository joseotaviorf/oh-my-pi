SELECT
    id,
    load_id AS id_load,
    collector_id AS id_collector,
    entity_id AS id_entity,
    entity,
    status,
    payload,
    response_payload,
    rev,
    event_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.collector_load
