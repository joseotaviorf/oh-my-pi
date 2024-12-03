SELECT
    id,
    folder_id AS id_folder,
    document_context_id AS id_document_context,
    context_external_id AS id_context_external,
    document_type_id AS id_document_type,
    country_code,
    attributes,
    attachments,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.document
