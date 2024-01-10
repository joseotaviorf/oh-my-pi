SELECT
    id,
    load_id AS id_load,
    collector_id AS id_collector,
    entity_id AS id_entity,
    entity,
    status,
    payload,
    response_payload,
    created_at AS dt_created,
    updated_at AS dt_updated
FROM datalake_trato_feito_raw.collector_load
