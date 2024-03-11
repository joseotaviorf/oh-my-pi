SELECT
    id,
    document_generation_id AS id_document_generation,
    external_id AS id_external,
    eviction_id AS id_eviction,
    flow,
    step,
    flow_status,
    step_status,
    finished_steps,
    step_status_reason,
    created_at AS ts_created,
    document_generation_created_at AS ts_document_generation_created,
    document_generation_updated_at AS ts_document_generation_updated
FROM datalake_trato_feito_raw.document_generation_aud
