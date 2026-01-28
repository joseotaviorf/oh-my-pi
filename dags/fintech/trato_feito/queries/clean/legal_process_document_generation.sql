SELECT
    id,
    legal_process_id AS id_legal_process,
    type,
    status,
    file_path,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM datalake_trato_feito_raw.legal_process_document_generation
