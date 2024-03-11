SELECT
    id,
    entity_id AS id_entity,
    entity_type,
    status,
    created_at AS dt_created,
    updated_at AS dt_updated
FROM datalake_trato_feito_raw.status_sync
