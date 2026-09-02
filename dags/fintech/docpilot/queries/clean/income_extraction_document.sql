SELECT
    id,
    batch_id AS id_batch,
    platform_document_id AS id_platform_document,
    file_path,
    classified_document_type,
    extraction_result,
    inclusion_result,
    error,
    ts_created
FROM
    datalake_docpilot_raw.incomeextractiondocument
