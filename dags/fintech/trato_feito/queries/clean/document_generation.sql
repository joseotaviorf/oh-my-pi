SELECT
    id,
    external_id AS id_external,
    eviction_id AS id_eviction,
    flow,
    step,
    flow_status,
    step_status,
    finished_steps,
    step_status_reason,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.document_generation
