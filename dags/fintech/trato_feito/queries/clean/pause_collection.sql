SELECT
    id,
    entity_id AS id_entity,
    entity_type,
    version,
    reason,
    request_by,
    active AS is_active,
    start_at AS dt_started,
    end_at AS dt_ended,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.pause_collection
