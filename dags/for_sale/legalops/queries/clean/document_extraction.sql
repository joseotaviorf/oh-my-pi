SELECT
    id,
    docpilot_external_id,
    status,
    extractor,
    error_message,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.document_extraction
