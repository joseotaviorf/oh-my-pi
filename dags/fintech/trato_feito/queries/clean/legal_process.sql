SELECT
    id,
    external_id AS id_external,
    entity_id AS id_entity,
    process_type,
    entity_type,
    law_firm,
    status,
    active AS is_active,
    status_order,
    version,
    last_update_event_at AS ts_last_update_event,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM datalake_trato_feito_raw.legal_process
